import Darwin

if let askPassExitCode = SSHLoginPasswordAskPassCommand.runIfRequested() {
    exit(askPassExitCode)
}

TerminullApp.main()
