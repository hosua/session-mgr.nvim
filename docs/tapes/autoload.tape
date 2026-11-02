# docs/tapes/autoload.tape: plain nvim in a project with autosave.vim loads it and prints the hint.
# Regenerate:  bash docs/tapes/capture.sh autoload
# Rows shown:  startup autoload message (docs/tapes/FEATURES.md)
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
Type "export PS1='$ ' HISTFILE=/dev/null INIT=$PWD/docs/tapes/init.lua DEMO_ROOT=/tmp/session-mgr-demo/auto"
Enter
Type 'nvim() { command nvim --clean -u "$INIT" "$@"; }; cd $DEMO_ROOT/work && clear'
Enter
Show

Type "nvim"
Enter
Sleep 3s
Screenshot docs/media/autoload.png
Sleep 500ms
