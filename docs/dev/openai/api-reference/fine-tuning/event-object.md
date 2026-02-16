# The fine-tuning job event object

Fine-tuning job event object

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `fine_tuning.job.event` | The object type, which is always "fine_tuning.job.event". |
| `id` | string | Yes |  |  | The object identifier. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the fine-tuning job was created. |
| `level` | string | Yes |  | `info`, `warn`, `error` | The log level of the event. |
| `message` | string | Yes |  |  | The message of the event. |
| `type` | string | No |  | `message`, `metrics` | The type of event. |
| `data` | object | No |  |  | The data associated with the event. |

## Property Details

### `object` (required)

The object type, which is always "fine_tuning.job.event".

**Type**: string

**Allowed values**: `fine_tuning.job.event`

### `id` (required)

The object identifier.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) for when the fine-tuning job was created.

**Type**: integer

### `level` (required)

The log level of the event.

**Type**: string

**Allowed values**: `info`, `warn`, `error`

### `message` (required)

The message of the event.

**Type**: string

### `type`

The type of event.

**Type**: string

**Allowed values**: `message`, `metrics`

### `data`

The data associated with the event.

**Type**: object

## Example

```json
{
  "object": "fine_tuning.job.event",
  "id": "ftevent-abc123"
  "created_at": 1677610602,
  "level": "info",
  "message": "Created fine-tuning job",
  "data": {},
  "type": "message"
}

```

