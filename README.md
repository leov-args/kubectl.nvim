# kubectl.nvim

A Neovim plugin to interact with Kubernetes pods using Telescope. Provides a fast, cached interface for managing pods, viewing logs, and performing common operations.

## Features

- 📋 **Pod Management**: List pods and containers with rich information (status, age, restart count)
- 🔄 **Smart Caching**: 30-second cache with manual refresh to reduce kubectl calls
- 🌐 **Namespace Support**: Toggle between current/all namespaces, or select a specific namespace
- 📊 **Restart Count**: Monitor container stability with visible restart counts
- 📝 **Flexible Logs**: View logs in tmux or directly in Neovim buffers
- 🚀 **Quick Actions**: Restart deployments and update images interactively
- ⚡ **Streaming Logs**: Real-time log streaming with follow mode
- 🎨 **Clean UI**: Namespace-aware display without repetition

## Requirements

- Neovim 0.5+
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `kubectl` installed and configured
- [tmux](https://github.com/tmux/tmux) (optional, only for tmux log mode)

## Installation

### Using lazy.nvim

```lua
{
  'your-username/kubectl.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('kubectl').setup()
  end
}
```

### Using packer.nvim

```lua
use {
  'your-username/kubectl.nvim',
  requires = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('kubectl').setup()
  end
}
```

## Configuration

All options are optional. Here are the defaults:

```lua
require('kubectl').setup({
  -- Logging & Notifications
  log_level = vim.log.levels.INFO,
  notify_timeout = 5000,

  -- Tmux Integration (backward compatibility)
  tmux_split_cmd = "tmux split-window -h '%s; read'",

  -- Cache Settings
  cache_ttl = 30,              -- Cache duration in seconds
  auto_refresh = true,         -- Enable background refresh
  auto_refresh_interval = 30,  -- Refresh interval in seconds

  -- Log Output
  log_output = "tmux",         -- "tmux" | "buffer"
  log_buffer_split = "vsplit", -- "vsplit" | "split" | "tabnew"
  log_follow_mode = true,      -- Auto-scroll logs to end

  -- Namespace Settings
  namespace_mode = "current",  -- "current" | "all"

  -- UI Display
  show_restart_count = true,
  display_format = {
    pod_name_width = 40,
    image_width = 50,
    status_width = 10,
    age_width = 8,
    restarts_width = 8,
    namespace_width = 15,
  },
})
```

### Configuration Examples

**View logs in Neovim buffers instead of tmux:**

```lua
require('kubectl').setup({
  log_output = "buffer",
  log_buffer_split = "vsplit",  -- or "split", "tabnew"
})
```

**Start with all namespaces view:**

```lua
require('kubectl').setup({
  namespace_mode = "all",
})
```

**Increase cache duration for large clusters:**

```lua
require('kubectl').setup({
  cache_ttl = 60,  -- 1 minute cache
})
```

## Usage

### Basic Commands

Call the main function from Neovim:

```lua
require('kubectl').list_pods()
```

Or create a keymap:

```lua
vim.keymap.set('n', '<leader>kp', '<cmd>lua require("kubectl").list_pods()<CR>', { desc = 'Kubernetes Pods' })
```

### Keymaps

#### In the Telescope Picker

| Key     | Action                                              |
| ------- | --------------------------------------------------- |
| `<CR>`  | View logs for selected pod/container                |
| `<C-n>` | Toggle between current namespace and all namespaces |
| `<C-s>` | Select a specific namespace                         |
| `<C-f>` | Force refresh (bypass cache)                        |
| `<C-r>` | Restart the selected deployment                     |
| `<C-i>` | Update image version for selected container         |

#### In Log Buffers (when using buffer output)

| Key     | Action             |
| ------- | ------------------ |
| `q`     | Close log buffer   |
| `<C-c>` | Stop log streaming |

### Display Information

The Telescope picker displays:

- **Pod Name**: Container name (or pod name if only one container)
- **Image**: Container image with version
- **Status**: Container status (Running, Completed, Error, etc.)
- **Age**: Time since pod creation
- **Restarts**: Number of container restarts
- **Namespace**: Shown only when viewing all namespaces

### Examples

**Quick pod inspection:**

```lua
-- List pods in current namespace
:lua require('kubectl').list_pods()

-- Inside picker, press <C-n> to toggle all namespaces
-- Or press <C-s> to select a specific namespace
-- Press <C-f> to refresh if you just deployed something
```

**View logs in buffer:**

```lua
require('kubectl').setup({ log_output = "buffer" })
-- Now when you press <CR> on a pod, logs open in a Neovim buffer
-- Press 'q' to close, <C-c> to stop streaming
```

**Restart a deployment:**

```lua
-- Select a pod in the picker and press <C-r>
-- Confirmation prompt will appear
```

## License

MIT License. See `LICENSE` file for details.

## Contributing

Contributions are welcome! If you have ideas, bug fixes, or improvements, feel
free to open a pull request. Please ensure your code follows the existing style
and includes relevant documentation or comments.

Before submitting a PR:

- Check that your changes work as expected.
- Run tests if available.
- Describe your changes clearly in the PR description.

## Issues

If you encounter any problems or have feature requests, please open an issue
on the [GitHub Issues page](https://github.com/levargas0584/kubectl.nvim/issues).
Provide as much detail as possible, including your Neovim version, operating system,
and steps to reproduce the issue.
