# docs/tapes/picker-autosave-on.tape: the picker footer reads "s autosave on" when autosave is enabled.
# Regenerate:  bash docs/tapes/capture.sh picker-autosave-on
# Rows shown:  picker autosave footer (docs/tapes/FEATURES.md)
Require bash
Set Shell "bash"
Set FontSize 15
Set Width 1100
Set Height 600
Set Padding 14
Set TypingSpeed 60ms
Set Theme "Catppuccin Mocha"
Set CursorBlink false

Hide
Type "export PS1='$ ' HISTFILE=/dev/null INIT=$PWD/tests/smoke/init.lua SMOKE_ROOT=/tmp/session-mgr-demo/picker"
Enter
Type 'nvim() { command nvim --clean -u "$INIT" "$@"; }; cd $SMOKE_ROOT/work && clear'
Enter
Show
Type "nvim"
Enter
Sleep 2s
Type " sl"
Sleep 1500ms
Screenshot docs/media/picker-autosave-on.png
Sleep 500ms
