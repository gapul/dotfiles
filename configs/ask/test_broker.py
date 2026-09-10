"""Smallest checks that fail if the parts that matter break.

    nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (ps: [ ps.mcp ps.websockets ])' \
      --command python3 broker/test_broker.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import ask_broker as broker


def test_yes_words():
    for word in ["yes", "Y", " ok ", "承認", "approve"]:
        assert broker.is_yes(word), word
    for word in ["no", "", None, "maybe", "yesterday"]:
        assert not broker.is_yes(word), word


def test_allowlist_refuses_before_touching_the_vault():
    """The refusal has to happen without a human and without the vault: that is the whole point of
    having an allowlist rather than relying on the approval."""
    broker.CONFIG = broker.replace_allowlist(("github.com",))

    async def run():
        return await broker.login_fill(
            ctx=None, domain="evil.example", selectors={"password": "#p"}, requester="test"
        )

    result = asyncio.run(run())
    assert result["filled"] is False, result
    assert "allowlist" in result["error"], result


def test_refuses_to_listen_wide_open():
    """The check that matters is not that auth works, but that it cannot be skipped by accident:
    binding beyond loopback without a token has to stop the process, not warn."""
    import dataclasses

    original = broker.CONFIG
    try:
        broker.CONFIG = dataclasses.replace(original, host="100.64.0.1", token_file="")
        try:
            broker.main()
        except SystemExit as exc:
            assert "token_file" in str(exc), exc
        else:
            raise AssertionError("started anyway")
    finally:
        broker.CONFIG = original


def test_elicitation_results_map_to_answers():
    """The first live call failed here: elicit() needs a pydantic schema, not None, and the reader
    was guessing at the result shape. Both ends are now pinned by this."""
    from mcp.server.elicitation import AcceptedElicitation, CancelledElicitation, DeclinedElicitation

    assert broker._elicit_answer(AcceptedElicitation(data=broker.YesNo(approved=True))) == "yes"
    assert broker._elicit_answer(AcceptedElicitation(data=broker.YesNo(approved=False))) == "no"
    assert broker._elicit_answer(AcceptedElicitation(data=broker.Choice(choice="b"))) == "b"
    assert broker._elicit_answer(AcceptedElicitation(data=broker.FreeText(text="hi"))) == "hi"
    # Declining is a no; cancelling is not an answer and must fall through to the next channel.
    assert broker._elicit_answer(DeclinedElicitation()) == "no"
    assert broker._elicit_answer(CancelledElicitation()) is None

    assert broker._schema_for("approve") is broker.YesNo
    assert broker._schema_for("login_fill") is broker.YesNo
    assert broker._schema_for("choose") is broker.Choice
    assert broker._schema_for("ask_text") is broker.FreeText


def test_applescript_strings_are_escaped():
    """The prompt carries a reason and a requester name that arrived over the wire, and it is
    pasted into a script. Quotes and backslashes have to stop being quotes and backslashes."""
    assert broker._as_applescript_string('say "hi"') == '"say \\"hi\\""'
    assert broker._as_applescript_string("back\\slash") == '"back\\\\slash"'
    # display dialog takes one line; a newline in the middle would end the literal.
    assert "\n" not in broker._as_applescript_string("two\nlines")


def test_tools_registered():
    names = {t.name for t in asyncio.run(broker.mcp.list_tools())}
    assert names == {"approve", "choose", "ask_text", "login_fill"}, names


def test_no_tool_returns_a_credential():
    """If a tool ever grows a way to hand back a secret, this is the line that should stop it."""
    for tool in asyncio.run(broker.mcp.list_tools()):
        text = (tool.description or "").lower()
        assert "returns the password" not in text
    assert not hasattr(broker, "get_password")


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
    print("all good")
