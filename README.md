# kubectl.nvim

A Neovim plugin to interact with Kubernetes pods using Telescope.

## Features

- List Kubernetes pods and containers.
- View logs in a tmux split.
- Restart deployments.
- Update container image versions interactively.

## Requirements

- Neovim 0.5+
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [tmux](https://github.com/tmux/tmux)
- `kubectl` installed and configured.

## Installation

### Using lazy.nvim

```lua
{
  'lvargas0584/kubectl.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' }
}
```

### Using packer.nvim

```lua
use {
  'lvargas0584/kubectl.nvim',
  requires = { 'nvim-telescope/telescope.nvim' }
}
```

## Configuration

You can configure the plugin using the `setup` function. Example:

```lua
require('kubectl').setup({
  log_level = vim.log.levels.WARN,
  tmux_split_cmd = "tmux split-window -v '%s; read'",
  notify_timeout = 3000,
})
```

## Usage

Call the main function from your Neovim config or command line:

```lua
require('kubectl').list_pods()
```

### Key Bindings in the Telescope picker

- `<CR>`: Show logs for the selected pod in a tmux split.
- `<C-r>`: Restart the selected deployment.
- `<C-i>`: Change the image version for the selected container.

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
