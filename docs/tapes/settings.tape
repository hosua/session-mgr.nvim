# docs/tapes/settings.tape: `:SessionMgr settings` shows the settings menu.
# Regenerate:  bash docs/tapes/capture.sh settings
# Rows shown:  settings menu (docs/tapes/FEATURES.md)
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
Type "export PS1='$ ' HISTFILE=/dev/null INIT=$PWD/docs/tapes/init.lua DEMO_ROOT=/tmp/session-mgr-demo/picker"
Enter
Type 'nvim() { command nvim --clean -u "$INIT" "$@"; }; cd $DEMO_ROOT/work && clear'
Enter
Show

Type "nvim"
Enter
Sleep 3s
Type ":SessionMgr settings"
Enter
Sleep 1s
Screenshot docs/media/settings.png
Sleep 500ms
