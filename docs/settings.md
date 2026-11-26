# Settings

[Back to setup](../README.md).

## Configuration

```lua
require("paj").setup({
  command = "paj",
  timeout = 300,
  output_size = 30,
  output_position = "bottom",
  max_request_bytes = 200 * 1024,
})
```

| Option              | Description                                                          |
| ------------------- | -------------------------------------------------------------------- |
| `command`           | Paj executable name or path                                          |
| `timeout`           | Bridge request timeout in seconds                                    |
| `output_size`       | Response split size as a percentage from `1` to `100`                |
| `output_position`   | Response split position: `"top"`, `"bottom"`, `"left"`, or `"right"` |
| `max_request_bytes` | Maximum encoded editor request size accepted by the plugin           |

For top and bottom splits, `output_size` is a percentage of the editor height. For left and right
splits, it is a percentage of the editor width.

Requests are encoded as JSON and piped directly to `paj bridge request --request-stdin`; they are
not stored in temporary files.

## Edit in place

These optional settings affect only `:PajEdit`:

```lua
require("paj").setup({
  edit = {
    model = "provider/model-id",
    thinking = "low",
  },
})
```

| Option          | Default                        | Description                                  |
| --------------- | ------------------------------ | -------------------------------------------- |
| `edit.command`  | `"pi"`                         | Pi executable name or path                   |
| `edit.model`    | Pi's configured default model  | Pi model selector, typically `provider/id`    |
| `edit.thinking` | Pi's normal thinking selection | `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, or `max` |
| `edit.timeout`  | `120`                          | Headless request timeout in seconds           |

Remove either override to let Pi choose that setting. Available thinking levels depend on the model.
Models must be available without loading Pi extensions.
