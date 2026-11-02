# docs/tapes/new-session.tape: <leader>sn saves autosave.vim, then leaves nothing open.
# Regenerate:  bash docs/tapes/capture.sh new-session
# Rows shown:  :SessionMgr new (docs/tapes/FEATURES.md)
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

Type "nvim a.txt"
Enter
Sleep 2s
Type " sn"
Sleep 1500ms
Screenshot docs/media/new-session.png
Sleep 500ms
