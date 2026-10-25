' Modified for Anmir; see NOTICE for downstream changes.
strCommand = "cmd /c anmir.exe"

For Each Arg In WScript.Arguments
    strCommand = strCommand & " """ & replace(Arg, """", """""""""") & """"
Next

CreateObject("Wscript.Shell").Run strCommand, 0, false
