# Managed by setup-ubuntu-workstation: Go on the PATH of every login session.
case ":$PATH:" in *:/usr/local/go/bin:*) ;; *) PATH="/usr/local/go/bin:$PATH" ;; esac
case ":$PATH:" in *:"$HOME/go/bin":*) ;; *) PATH="$HOME/go/bin:$PATH" ;; esac
export PATH
