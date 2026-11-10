"""Replay captured royale states through the installed MaaFramework pipeline.

Uses a debug controller: no game window, real input, mail, or notifications.
Run with: python -X utf8 tools/test-royale-replay.py
"""

import argparse
import ctypes as c
from datetime import datetime, timedelta
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
SUCCEEDED = 3000


class Runtime:
    def __init__(self):
        self.dll_dir = os.add_dll_directory(str(ROOT / "maafw"))
        self.lib = c.CDLL(str(ROOT / "maafw/MaaFramework.dll"))
        ptr, i64, u64, string = c.c_void_p, c.c_int64, c.c_uint64, c.c_char_p
        self.callback_type = c.CFUNCTYPE(None, ptr, string, string, ptr)
        signatures = {
            "MaaGlobalSetOption": (c.c_bool, c.c_int32, ptr, u64),
            "MaaResourceCreate": (ptr,),
            "MaaResourceDestroy": (None, ptr),
            "MaaResourcePostBundle": (i64, ptr, string),
            "MaaResourceWait": (c.c_int32, ptr, i64),
            "MaaResourceSetOption": (c.c_bool, ptr, c.c_int32, ptr, u64),
            "MaaCustomControllerCreate": (ptr, ptr, ptr),
            "MaaImageBufferSetEncoded": (c.c_bool, ptr, ptr, u64),
            "MaaStringBufferCreate": (ptr,),
            "MaaStringBufferDestroy": (None, ptr),
            "MaaStringBufferGet": (string, ptr),
            "MaaStringBufferSet": (c.c_bool, ptr, string),
            "MaaControllerDestroy": (None, ptr),
            "MaaControllerPostConnection": (i64, ptr),
            "MaaControllerWait": (c.c_int32, ptr, i64),
            "MaaControllerSetOption": (c.c_bool, ptr, c.c_int32, ptr, u64),
            "MaaTaskerCreate": (ptr,),
            "MaaTaskerDestroy": (None, ptr),
            "MaaTaskerBindResource": (c.c_bool, ptr, ptr),
            "MaaTaskerBindController": (c.c_bool, ptr, ptr),
            "MaaTaskerAddContextSink": (i64, ptr, self.callback_type, ptr),
            "MaaTaskerPostTask": (i64, ptr, string, string),
            "MaaTaskerStatus": (c.c_int32, ptr, i64),
            "MaaTaskerPostStop": (i64, ptr),
            "MaaTaskerWait": (c.c_int32, ptr, i64),
        }
        for name, signature in signatures.items():
            fn = getattr(self.lib, name)
            fn.restype, fn.argtypes = signature[0], list(signature[1:])
            setattr(self, name, fn)
        level = c.c_int32(0)
        self.MaaGlobalSetOption(4, c.byref(level), c.sizeof(level))
        log_dir = str(ROOT / "debug/royale-replay").encode()
        self.MaaGlobalSetOption(1, c.c_char_p(log_dir), len(log_dir))
        self.resource = self.MaaResourceCreate()
        provider = c.c_int32(1)
        self.MaaResourceSetOption(self.resource, 2, c.byref(provider), c.sizeof(provider))
        job = self.MaaResourcePostBundle(self.resource, str(ROOT / "resource").encode())
        assert self.MaaResourceWait(self.resource, job) == SUCCEEDED, "Resource loading failed"
        self.agent = c.CDLL(str(ROOT / "maafw/MaaAgentClient.dll"))
        for name, restype, args in [
            ("CreateV2", ptr, [ptr]), ("Destroy", None, [ptr]),
            ("Identifier", c.c_bool, [ptr, ptr]), ("BindResource", c.c_bool, [ptr, ptr]),
            ("SetTimeout", c.c_bool, [ptr, i64]), ("Connect", c.c_bool, [ptr]),
            ("Disconnect", c.c_bool, [ptr]),
        ]:
            func = getattr(self.agent, "MaaAgentClient" + name)
            func.restype, func.argtypes = restype, args
        self.client = self.agent.MaaAgentClientCreateV2(None)
        identifier = self.MaaStringBufferCreate()
        try:
            assert self.agent.MaaAgentClientIdentifier(self.client, identifier)
            socket = self.MaaStringBufferGet(identifier).decode()
        finally:
            self.MaaStringBufferDestroy(identifier)
        assert self.agent.MaaAgentClientBindResource(self.client, self.resource)
        self.clock = subprocess.Popen([str(ROOT / "tools/bjx-royale-clock.exe"), socket], cwd=ROOT,
                                      creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            assert self.agent.MaaAgentClientSetTimeout(self.client, 5000)
            assert self.agent.MaaAgentClientConnect(self.client), "Royale clock connection failed"
            assert self.agent.MaaAgentClientSetTimeout(self.client, 130000)
        except BaseException:
            self.close()
            raise

    def replay(self, image, entry, targets, patches=None, frame_after=None, time_limit=8):
        ctrl = tasker = None
        trace = []

        # MaaCustomControllerCallbacks layout from the bundled MaaCustomController.h.
        fields = ["connect", "connected", "request_uuid", "get_features", "start_app",
                  "stop_app", "screencap", "click", "swipe", "touch_down", "touch_move",
                  "touch_up", "click_key", "input_text", "key_down", "key_up", "scroll",
                  "relative_move", "shell", "inactive", "get_info"]
        class Callbacks(c.Structure):
            _fields_ = [(name, c.c_void_p) for name in fields]
        callbacks = Callbacks()
        keepalive = []
        ptr, i32, string = c.c_void_p, c.c_int32, c.c_char_p
        def register(name, function, *args, result=c.c_bool):
            callback = c.CFUNCTYPE(result, *args)(function)
            keepalive.append(callback)
            setattr(callbacks, name, c.cast(callback, ptr))
        for name in ["connect", "connected", "inactive"]:
            register(name, lambda arg: True, ptr)
        register("request_uuid", lambda arg, buf: self.MaaStringBufferSet(buf, b"BJX-replay"), ptr, ptr)
        register("get_features", lambda arg: 0, ptr, result=c.c_uint64)
        encoded = {"png": image.read_bytes()}
        transitions = {name: iter(paths) for name, paths in (frame_after or {}).items()}
        register("screencap", lambda arg, buf: self.MaaImageBufferSetEncoded(buf, c.c_char_p(encoded["png"]), len(encoded["png"])), ptr, ptr)
        for name in ["click", "scroll", "relative_move"]:
            register(name, lambda x, y, arg: True, i32, i32, ptr)
        register("swipe", lambda x1, y1, x2, y2, duration, arg: True, i32, i32, i32, i32, i32, ptr)
        for name in ["touch_down", "touch_move"]:
            register(name, lambda contact, x, y, pressure, arg: True, i32, i32, i32, i32, ptr)
        for name in ["touch_up", "click_key", "key_down", "key_up"]:
            register(name, lambda key, arg: True, i32, ptr)
        for name in ["start_app", "stop_app", "input_text"]:
            register(name, lambda text, arg: True, string, ptr)

        @self.callback_type
        def on_event(handle, message, details, arg):
            if message == b"Node.Action.Starting":
                name = json.loads(details)["name"]
                trace.append(name)
                if name in transitions:
                    next_frame = next(transitions[name], None)
                    if next_frame:
                        encoded["png"] = next_frame.read_bytes()

        override = {}
        for path in (ROOT / "resource/pipeline").rglob("*.json"):
            for name, node in json.loads(path.read_text(encoding="utf-8-sig")).items():
                patch = {"pre_delay": 0, "post_delay": 0, "rate_limit": 0}
                if node.get("action") == "Command":
                    patch["action"] = "DoNothing"
                if node.get("custom_action") == "BJX_ROYALE_CHECK_DEADLINE":
                    patch["custom_action_param"] = 0
                override[name] = patch
        override["单人吃鸡刷币"]["custom_action_param"] = (datetime.now() + timedelta(hours=1)).strftime("%H:%M")
        if entry != "单人吃鸡刷币":
            override["单人吃鸡刷币"]["next"] = [entry]
        for name, patch in (patches or {}).items():
            override[name] = {**override.get(name, {}), **patch}
        for name in targets:
            override[name] = {**override.get(name, {}), "action": "StopTask"}
        try:
            ctrl = self.MaaCustomControllerCreate(c.byref(callbacks), None)
            assert ctrl, "Debug controller creation failed"
            raw = c.c_bool(True)
            self.MaaControllerSetOption(ctrl, 3, c.byref(raw), c.sizeof(raw))
            assert self.MaaControllerWait(ctrl, self.MaaControllerPostConnection(ctrl)) == SUCCEEDED
            tasker = self.MaaTaskerCreate()
            assert self.MaaTaskerBindResource(tasker, self.resource)
            assert self.MaaTaskerBindController(tasker, ctrl)
            self.MaaTaskerAddContextSink(tasker, on_event, None)
            job = self.MaaTaskerPostTask(tasker, "单人吃鸡刷币".encode(), json.dumps(override, ensure_ascii=False).encode())
            deadline = time.monotonic() + time_limit
            while self.MaaTaskerStatus(tasker, job) in (1000, 2000) and time.monotonic() < deadline:
                time.sleep(0.02)
            assert self.MaaTaskerStatus(tasker, job) == SUCCEEDED, f"Replay failed or timed out: {trace}"
            return trace
        finally:
            if tasker:
                self.MaaTaskerWait(tasker, self.MaaTaskerPostStop(tasker))
                self.MaaTaskerDestroy(tasker)
            if ctrl:
                self.MaaControllerDestroy(ctrl)

    def close(self):
        self.agent.MaaAgentClientDisconnect(self.client)
        self.agent.MaaAgentClientDestroy(self.client)
        try:
            self.clock.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.clock.terminate()
            self.clock.wait(timeout=2)
        self.MaaResourceDestroy(self.resource)
        self.dll_dir.close()


def assert_round_lock():
    """No recognition result or error may reopen matching before the exit node."""
    nodes = {}
    for path in (ROOT / "resource/pipeline").rglob("*.json"):
        nodes.update(json.loads(path.read_text(encoding="utf-8-sig")))
    forbidden = {"单人吃鸡刷币", "吃鸡检查窗口", "吃鸡识别入口", "吃鸡判断主城", "主城打开绝境",
                 "主界面打开绝境", "打开绝境", "点个人匹配", "提交个人匹配", "记下飞沙令剩余", "再来一局"}
    starts = ["提交个人匹配", "匹配后等待排队", "确认正在匹配", "等进局", "离队再看2",
              "确认已在局内", "记下进局时间", "局内看看", "局内按1"]
    for start in starts:
        pending, seen = [(start, [start])], set()
        while pending:
            name, route = pending.pop()
            assert len(route) == 1 or name not in forbidden, "未见退出页可重新匹配: " + " → ".join(route)
            if name == "看到结算" or name in seen:
                continue
            seen.add(name)
            node = nodes[name]
            if node.get("action") == "StopTask":
                continue
            for edge in node.get("next", []) + node.get("on_error", []):
                target = edge if isinstance(edge, str) else edge["name"]
                pending.append((target, route + [target]))
    print(f"PASS: {len(starts)} 个本局入口的所有识别／异常路径，退出页之前均不能回到匹配", flush=True)


def assert_waits_do_not_expire_between_rounds():
    nodes = json.loads((ROOT / "resource/pipeline/solo_royale.json").read_text(encoding="utf-8-sig"))
    for name in ["进局后等待画面", "本局等待画面", "退出后等待主城"]:
        assert "max_hit" not in nodes[name], f"{name}: 正常等待不能使用跨整次运行累计的 max_hit"
    print("PASS: 准备、局内和退出后等待不会因多局累计次数耗尽而停止", flush=True)


def main():
    from PIL import Image

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, help="Replay a local full-size captured frame instead of the cropped fixture")
    opts = parser.parse_args()
    output = ROOT / "debug/royale-replay"
    output.mkdir(parents=True, exist_ok=True)
    frames = {}
    for name, position in [("canghai", (1680, 0)), ("main-menu", (1250, 0)), ("main-menu-light", (1240, 0)),
                           ("battle-hud", (1400, 0)), ("battle-no-timer", (1400, 0)),
                           ("preparing", (1400, 0)), ("queue", (1335, 870)),
                           ("settlement", (1200, 950)), ("quota-icon", (350, 630)),
                           ("quota-three-digits", (350, 630)), ("quota-zero", (350, 630)),
                           ("loading", None)]:
        if opts.image:
            break
        image = Image.new("RGB", (1920, 1080))
        if position:
            fixture = ROOT / f"tests/fixtures/royale/{name}.png"
            if not fixture.is_file():
                parser.error(f"缺少本机回归样本 {name}.png；公开源码包不带游戏截图，请按 tests/fixtures/royale/README.md 自行采集，或用 --image 重放本机完整截图。")
            with Image.open(fixture) as label:
                image.paste(label, position)
        frames[name] = output / f"{name}.png"
        image.save(frames[name])
    cases = [
        ("剩余82不能把飞沙令图标读成数字", "quota-icon", "确认单人页", "匹配后等待排队", {}),
        ("剩余三位数仍能识别", "quota-three-digits", "确认单人页", "点个人匹配", {}),
        ("剩余为零结束且不再匹配", "quota-zero", "确认单人页", "通知完成", {}),
        ("主城启动", "canghai", "单人吃鸡刷币", "打开绝境", {}),
        ("主城排下一局", "canghai", "再来一局", "打开绝境", {}),
        ("普通主界面启动", "main-menu", "单人吃鸡刷币", "打开绝境", {}),
        ("新号浅色主界面启动", "main-menu-light", "单人吃鸡刷币", "打开绝境", {}),
        ("新号退出确认后允许重排", "main-menu-light", "退出后确认主城", "打开绝境", {}),
        ("新号未见退出页不能重排", "main-menu-light", "局内看看", "本局等待画面", {}),
        ("新号排队消失尚未进局不能重排", "main-menu-light", "离队再看2", "进局后等待画面", {}),
        ("未见退出页即使像主城也不能重排", "canghai", "局内看看", "本局等待画面", {}),
        ("退出后只打一局结束", "canghai", "退出后确认主城", "通知完成", {"再来一局": {"enabled": False}}),
        ("排队消失仍像主城也不能重排", "canghai", "离队再看2", "进局后等待画面", {}),
        ("排队启动", "queue", "单人吃鸡刷币", "等进局", {}),
        ("局内出现排队面板不能重排", "queue", "局内看看", "本局等待画面", {}),
        ("局内启动", "battle-hud", "单人吃鸡刷币", "局内按1", {}),
        ("局内继续", "battle-hud", "局内看看", "局内按1", {}),
        ("局内倒计时隐藏仍可继续", "battle-no-timer", "局内看看", "局内按1", {}),
        ("准备阶段尚无剩余人数", "preparing", "单人吃鸡刷币", "吃鸡未知画面等待", {}),
        ("加载不能当进局", "loading", "单人吃鸡刷币", "吃鸡未知画面等待", {}),
        ("排队消失仍须确认局内", "loading", "离队再看2", "进局后等待画面", {}),
        ("局内突然黑屏", "loading", "局内看看", "本局等待画面", {}),
        ("未知画面达到等待上限", "loading", "单人吃鸡刷币", "留下截图",
         {"吃鸡未知画面等待": {"max_hit": 1}, "吃鸡检查局内": {"timeout": 30}}),
        ("结算启动", "settlement", "单人吃鸡刷币", "等加载", {}),
        ("局内结束", "settlement", "局内看看", "等加载", {}),
        ("只有传出战场也可确认退出", "settlement", "局内看看", "等加载",
         {"看到结算": {"any_of": [{"recognition": "OCR", "expected": "(传出|退出)战场", "roi": [1200, 950, 700, 130]}]}}),
    ]
    if opts.image:
        frames["original"] = opts.image.resolve()
        cases = [("原始故障画面", "original", "单人吃鸡刷币", "打开绝境", {})]
    targets = ["打开绝境", "局内按1", "等进局", "吃鸡未知画面等待", "进局后等待画面",
               "本局等待画面", "等加载", "通知完成", "点个人匹配"]
    runtime = Runtime()
    try:
        assert_round_lock()
        for label, frame, entry, expected, patches in cases:
            stops = targets if expected != "留下截图" else [name for name in targets if name != "吃鸡未知画面等待"] + ["留下截图"]
            if expected == "匹配后等待排队":
                stops = [name for name in stops if name != "点个人匹配"] + [expected]
            if frame == "quota-zero":
                stops = [name for name in targets if name != "通知完成"]
            trace = runtime.replay(frames[frame], entry, stops, patches)
            assert trace and trace[-1] == expected, f"{label}: expected {expected}, got {trace}"
            if frame == "quota-zero":
                assert trace.index("读到零额度") < trace.index("本周已满") < trace.index("关闭绝境"), trace
            if expected != "局内按1":
                assert "局内检查十分钟" not in trace, f"{label}: 不应检查局内按键计时"
            if label == "局内启动":
                assert "记下进局时间" in trace, "进局应初始化本局计时"
            if label == "局内继续":
                assert "记下进局时间" not in trace, "局内循环不能重置十分钟计时"
                assert "局内检查十分钟" in trace, "局内应同步检查十分钟按键"
            print(f"PASS {label}: " + " → ".join(trace), flush=True)
        if not opts.image:
            trace = runtime.replay(
                frames["quota-zero"], "确认单人页",
                ["通知完成", "点个人匹配", "关掉再开"],
                {"读到零额度": {"timeout": 150}},
                {"读到零额度": [frames["quota-icon"]]},
            )
            assert trace[-1] == "关掉再开" and "本周已满" not in trace, trace
            print("PASS: 两次额度读数不一致时重新核对", flush=True)
            for once in [False, True]:
                transitions = {
                    "进局后等待画面": [frames["preparing"], frames["battle-hud"]],
                    "局内按1": [frames["canghai"]],
                    "本局等待画面": [frames["settlement"]],
                    "等加载": [frames["loading"]],
                    "退出后等待主城": [frames["canghai"]],
                }
                patches = {"再来一局": {"enabled": False}} if once else {}
                trace = runtime.replay(frames["canghai"], "离队再看2",
                                       ["打开绝境", "通知完成", "留下截图"], patches, transitions)
                expected = "通知完成" if once else "打开绝境"
                assert trace[-1] == expected, trace
                for name in ["进局后等待画面", "本局等待画面", "看到结算", "退出后等待主城"]:
                    assert name in trace, (name, trace)
                boundary = trace.index("看到结算")
                assert not any(name in trace[:boundary] for name in ["再来一局", "打开绝境", "点个人匹配"]), trace
                label = "只打一局" if once else "继续下一局"
                print(f"PASS 连续画面({label}): 准备 → 局内 → 伪主城 → 退出页 → 加载 → 主城 → {expected}", flush=True)
            # Two rounds in ONE task/context. Earlier rounds must not consume the
            # next round's normal preparation wait allowance.
            transitions = {
                "进局后等待画面": [frames["battle-hud"], frames["battle-hud"]],
                "局内按1": [frames["settlement"], frames["settlement"]],
                "等加载": [frames["canghai"], frames["canghai"]],
                "再来一局": [frames["preparing"]],
            }
            patches = {
                "再来一局": {"max_hit": 1, "next": ["离队再看2"]},
                "进局后确认战场": {"timeout": 30},
            }
            trace = runtime.replay(frames["preparing"], "离队再看2",
                                   ["通知完成", "留下截图", "打开绝境"], patches, transitions)
            assert trace[-1] == "通知完成", f"多局等待不应耗尽后自动停止: {trace}"
            assert trace.count("局内按1") == 2, trace
            assert trace.count("看到结算") == 2, trace
            assert trace.count("单人吃鸡刷币") == 1, trace
            print("PASS 多局连续运行: 两局分别等待准备、进入战场、结算，第二局正常完成", flush=True)
            assert_waits_do_not_expire_between_rounds()
        print(f"PASS: {len(cases)} 个单画面用例、{0 if opts.image else 4} 个连续画面用例", flush=True)
    finally:
        runtime.close()


if __name__ == "__main__":
    main()
