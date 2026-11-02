# docs/tapes/picker-autosave-off.tape: pressing s in the picker flips the footer to "s autosave off".
# Regenerate:  bash docs/tapes/capture.sh picker-autosave-off
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
Type "s"
Sleep 1s
Screenshot docs/media/picker-autosave-off.png
Sleep 500ms
