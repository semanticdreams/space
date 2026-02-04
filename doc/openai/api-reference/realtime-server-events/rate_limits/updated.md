# rate_limits.updated

Emitted at the beginning of a Response to indicate the updated rate limits. 
When a Response is created some tokens will be "reserved" for the output 
tokens, the rate limits shown here reflect that reservation, which is then 
adjusted accordingly once the Response is completed.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `event_id` | string | Yes |  |  | The unique ID of the server event. |
| `type` | string | Yes |  | `rate_limits.updated` | The event type, must be `rate_limits.updated`. |
| `rate_limits` | array of object (4 properties) | Yes |  |  | List of rate limit information. |


### Items in `rate_limits` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `name` | string | No |  | `requests`, `tokens` | The name of the rate limit (`requests`, `tokens`). <br>  |
| `limit` | integer | No |  |  | The maximum allowed value for the rate limit. |
| `remaining` | integer | No |  |  | The remaining value before the limit is reached. |
| `reset_seconds` | number | No |  |  | Seconds until the rate limit resets. |

## Property Details

### `event_id` (required)

The unique ID of the server event.

**Type**: string

### `type` (required)

The event type, must be `rate_limits.updated`.

**Type**: string

**Allowed values**: `rate_limits.updated`

### `rate_limits` (required)

List of rate limit information.

**Type**: array of object (4 properties)

## Example

```json
{
    "event_id": "event_5758",
    "type": "rate_limits.updated",
    "rate_limits": [
        {
            "name": "requests",
            "limit": 1000,
            "remaining": 999,
            "reset_seconds": 60
        },
        {
            "name": "tokens",
            "limit": 50000,
            "remaining": 49950,
            "reset_seconds": 60
        }
    ]
}

```

