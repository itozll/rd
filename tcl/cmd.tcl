proc Cmd_ssh {args} {
  if {$args == ""} { error -601 }

  set svr [lindex $args 0]
  set cmd [lreplace $args 0 0]

  set server [ConfRemote $svr]

  if {$server != "" } {
    set gateway [ConfGateway $server]
    set ssh_cmd "ssh -A -tt [lindex $server 1][lindex $server 0]"
    set passwords "[lindex $server 2]"

    if {$gateway != ""} {
      set ssh_cmd "ssh -A -tt [lindex $gateway 1][lindex $gateway 0] $ssh_cmd"
      set passwords "[lindex $gateway 2] $passwords"
    }

    set command ""
    if {$cmd == ""} {
      global CONF_INTERACT

      set command [eval ConfAutoCommand [lindex $server 0] [lindex $server 3] [lindex $server 4]]
      if {$command != "" && !$CONF_INTERACT} {
        set ssh_cmd "$ssh_cmd $command"
        set command ""
      }
    } else {
      set ssh_cmd "$ssh_cmd $cmd"
    }

    command_spawn "$ssh_cmd" $passwords $command
  }
}

proc Cmd_list {args} {
  if {$args == ""} {
    ConfList ""
    return
  }

  ConfList [lindex $args 0]
}

proc Cmd_scp {args} {
  if {$args == "" } { error -603 }

  lassign $args src dest
  if {$dest == ""} { set dest . }

  command_exec "scp -r" $src $dest
}

proc Cmd_sshfs {args} {
  if {$args == "" } { error -604 }

  lassign $args src dest
  if {$dest == ""} {
    if {[string first $src :] == -1} {
      set src "$src:"
    }
    set dest .
  }

  if [command_check_path $src $dest] {
    set _src $src
    set _dest $dest
  } else {
    set _src $dest
    set _dest $src
  }

  if {$_dest == "."} {
    set a [split [file tail $_src] ":"]
    set b "sshfs.$a"

    set _dest [join $b ""]
  }

  if {[file exists $_dest]} {
    if {![file isdirectory $_dest]} {
      error -502
    }
  } else {
    file mkdir $_dest
  }

  if {![file isdirectory $_dest]} {
    error -503
  }

  command_exec "sshfs" $_src $_dest
}

####
proc command_check_path {src dest} {
  set a [string first ":" $src]
  set b [string first ":" $dest]

  if {$a == 0 || $b == 0} {
    error -500
  } elseif {$a > 0 && $b > 0} {
    error -501
  }

  if {$a > 0 && $b == -1} {return true} else {return false}
}

proc command_exec {cmdStr src {dest .} {checkLocal false}} {
  # true if scp remote local
  set tolocal true
  lassign "\"\"  $src $dest" svr srcpath destpath
  set pos [string first ":" $src]

  if {$pos > 0} {
    lassign [split $src ":"] svr srcpath
  } else {
    set tolocal false
    set pos [string first ":" $dest]
    if {$pos > 0} {
      lassign [split $dest ":"] svr destpath
    } else {
      # scp to user home path
      set svr $dest
      set destpath ""
    }
  }

  if {$svr == ""} {
    error -400
  }

  if {$checkLocal} {
    # scp remote local
    if {$tolocal} {
      if {[file exists $dest]} {
        if {![file isdirectory $dest]} {
          error -402
        }
      } else {
        file mkdir $dest
      }
    } else {
      # scp local remote
      if {![file exists $src]} {
        error -401
      }
    }
  }

  set server [ConfRemote $svr]
  if {$server == ""} {return }

  if {$tolocal} {
    set scp_cmd "[lindex $server 1][lindex $server 0]:$srcpath $destpath"
  } else {
    set scp_cmd "$srcpath [lindex $server 1][lindex $server 0]:$destpath"
  }

  set passwords "[lindex $server 2]"
  set gateway [ConfGateway $server]

  set CmdPrefix ""
  global TryRun
  if {!$TryRun} {
    set CmdPrefix "-ignore HUP"
  }

  if {$gateway == ""} {
    set scp_cmd "$CmdPrefix $cmdStr $scp_cmd"
  } else {
    set scp_cmd "$CmdPrefix $cmdStr -o \"ProxyCommand=ssh [lindex $gateway 1][lindex $gateway 0] nc %h %p\" $scp_cmd"
    set passwords "[lindex $gateway 2] $passwords"
  }

  command_spawn $scp_cmd $passwords
}

# run spawn
proc command_spawn {cmd {password ""} {command ""}} {
  global TryRun

  if {$TryRun} {
    puts " TryRun: $cmd"
    return
  }

  eval spawn $cmd
  foreach pwd $password {
    expect {
      "yes/no"        { send "yes\r"; set timeout 1; exp_continue }
      "(y/n)"         { send "y\r"; set timeout 1; exp_continue }
      "assword:"      { send "$pwd\r" }
      "\[#$]*$"       { break }
      {Permission denied} { return }
    }
  }

  expect {
    "yes/no"        { send "yes\r"; set timeout 1; exp_continue }
    "(y/n)"         { send "y\r"; set timeout 1; exp_continue }
    {]# $}          { if {$command != ""} { send "$command\r" } }
    {~$*}           { if {$command != ""} { send "$command\r" } }
    {Permission denied} { return }
  }

  interact
}
