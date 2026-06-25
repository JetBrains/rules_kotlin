load(
    "@bazel_skylib//lib:unittest.bzl",
    "asserts",
    "unittest",
)
load("//src/main/starlark/core/plugin:payload.bzl", "plugin_payload")

def _plugins_payload_json_encodes_empty_plugins_test_impl(ctx):
    env = unittest.begin(ctx)

    payload_json = plugin_payload.plugins_payload_json([])
    asserts.true(
        env,
        payload_json.startswith("{") and payload_json.endswith("}"),
        msg = "plugins payload should serialize to a JSON object",
    )
    asserts.true(
        env,
        "\"plugins\"" in payload_json,
        msg = "plugins payload should contain the plugins key",
    )

    return unittest.end(env)

plugins_payload_json_encodes_empty_plugins_test = unittest.make(
    _plugins_payload_json_encodes_empty_plugins_test_impl,
)

def _plugins_payload_json_encodes_populated_plugin_test_impl(ctx):
    env = unittest.begin(ctx)

    # Mirror the example parsed by PluginsPayloadParserTest.kt so the producer's emitted JSON
    # shape and the Kotlin proto/JsonFormat parser stay locked to the same contract: a drift in
    # either the JSON keys here or the proto field/enum names there breaks one of the two tests.
    plugin = struct(
        id = "plugin.test",
        classpath = depset([struct(path = "a.jar"), struct(path = "b.jar")]),
        options = [
            struct(key = "k1", value = "v1"),
            struct(key = "k2", value = "v2"),
        ],
        phases = ["compile", "stubs"],
    )

    decoded = json.decode(plugin_payload.plugins_payload_json([plugin]))

    asserts.equals(env, 1, len(decoded["plugins"]))
    plugin_json = decoded["plugins"][0]
    asserts.equals(env, "plugin.test", plugin_json["id"])
    asserts.equals(env, ["a.jar", "b.jar"], plugin_json["classpath"])
    asserts.equals(
        env,
        [{"key": "k1", "value": "v1"}, {"key": "k2", "value": "v2"}],
        plugin_json["options"],
    )

    # `phases` carries the proto enum *names* the JsonFormat parser maps to PluginPhase values.
    asserts.equals(env, ["PLUGIN_PHASE_COMPILE", "PLUGIN_PHASE_STUBS"], plugin_json["phases"])

    return unittest.end(env)

plugins_payload_json_encodes_populated_plugin_test = unittest.make(
    _plugins_payload_json_encodes_populated_plugin_test_impl,
)

def plugin_payload_test_suite(name):
    unittest.suite(
        name,
        plugins_payload_json_encodes_empty_plugins_test,
        plugins_payload_json_encodes_populated_plugin_test,
    )
