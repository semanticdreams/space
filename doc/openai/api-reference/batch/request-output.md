# The request output object

The per-line object of the batch output and error files

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | No |  |  |  |
| `custom_id` | string | No |  |  | A developer-provided per-request id that will be used to match outputs to inputs. |
| `response` | object (3 properties) | No |  |  |  |
|   ↳ `body` | map | No |  |  | The JSON body of the response |
| `error` | object (2 properties) | No |  |  | For requests that failed with a non-HTTP error, this will contain more information on the cause of the failure. |

## Property Details

### `id`

**Type**: string

### `custom_id`

A developer-provided per-request id that will be used to match outputs to inputs.

**Type**: string

### `response`

**Type**: object (3 properties)

**Nullable**: Yes

**Nested Properties**:

* `status_code`, `request_id`, `body`

### `error`

For requests that failed with a non-HTTP error, this will contain more information on the cause of the failure.

**Type**: object (2 properties)

**Nullable**: Yes

**Nested Properties**:

* `code`, `message`

## Example

```json
{"id": "batch_req_wnaDys", "custom_id": "request-2", "response": {"status_code": 200, "request_id": "req_c187b3", "body": {"id": "chatcmpl-9758Iw", "object": "chat.completion", "created": 1711475054, "model": "gpt-4o-mini", "choices": [{"index": 0, "message": {"role": "assistant", "content": "2 + 2 equals 4."}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 24, "completion_tokens": 15, "total_tokens": 39}, "system_fingerprint": null}}, "error": null}

```

