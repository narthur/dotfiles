-- tmux (prefix ctrl+a)
rex.bind("ctrl+a>ctrl+a", "pane.send_key", { key = "ctrl+a" })
rex.bind("ctrl+a>shift+\\", "pane.split", { direction = "right" })
rex.bind("ctrl+a>-", "pane.split", { direction = "down" })
rex.bind("ctrl+a>r", "client.config.reload")

-- Ghostty
rex.bind("shift+cmd+e", "pane.balance")
