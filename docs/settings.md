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
