# The message object

Represents a message within a [thread](/docs/api-reference/threads).

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `thread.message` | The object type, which is always `thread.message`. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the message was created. |
| `thread_id` | string | Yes |  |  | The [thread](/docs/api-reference/threads) ID that this message belongs to. |
| `status` | string | Yes |  | `in_progress`, `incomplete`, `completed` | The status of the message, which can be either `in_progress`, `incomplete`, or `completed`. |
| `incomplete_details` | object (1 property) | Yes |  |  | On an incomplete message, details about why the message is incomplete. |
| `completed_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the message was completed. |
| `incomplete_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the message was marked as incomplete. |
| `role` | string | Yes |  | `user`, `assistant` | The entity that produced the message. One of `user` or `assistant`. |
| `content` | array of oneOf: object (2 properties) | object (2 properties) | object (2 properties) | object (2 properties) | Yes |  |  | The content of the message in array of text and/or images. |
| `assistant_id` | string | Yes |  |  | If applicable, the ID of the [assistant](/docs/api-reference/assistants) that authored this message. |
| `run_id` | string | Yes |  |  | The ID of the [run](/docs/api-reference/runs) associated with the creation of this message. Value is `null` when messages are created manually using the create message or create thread endpoints. |
| `attachments` | array of object (2 properties) | Yes |  |  | A list of files attached to the message, and the tools they were added to. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |


### Items in `attachments` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `file_id` | string | No |  |  | The ID of the file to attach to the message. |
| `tools` | array of oneOf: object (1 property) | object (1 property) | No |  |  | The tools to add this file to. |

## Property Details

### `id` (required)

The identifier, which can be referenced in API endpoints.

**Type**: string

### `object` (required)

The object type, which is always `thread.message`.

**Type**: string

**Allowed values**: `thread.message`

### `created_at` (required)

The Unix timestamp (in seconds) for when the message was created.

**Type**: integer

### `thread_id` (required)

The [thread](/docs/api-reference/threads) ID that this message belongs to.

**Type**: string

### `status` (required)

The status of the message, which can be either `in_progress`, `incomplete`, or `completed`.

**Type**: string

**Allowed values**: `in_progress`, `incomplete`, `completed`

### `incomplete_details` (required)

On an incomplete message, details about why the message is incomplete.

**Type**: object (1 property)

**Nullable**: Yes

**Nested Properties**:

* `reason`

### `completed_at` (required)

The Unix timestamp (in seconds) for when the message was completed.

**Type**: integer

**Nullable**: Yes

### `incomplete_at` (required)

The Unix timestamp (in seconds) for when the message was marked as incomplete.

**Type**: integer

**Nullable**: Yes

### `role` (required)

The entity that produced the message. One of `user` or `assistant`.

**Type**: string

**Allowed values**: `user`, `assistant`

### `content` (required)

The content of the message in array of text and/or images.

**Type**: array of oneOf: object (2 properties) | object (2 properties) | object (2 properties) | object (2 properties)

### `assistant_id` (required)

If applicable, the ID of the [assistant](/docs/api-reference/assistants) that authored this message.

**Type**: string

**Nullable**: Yes

### `run_id` (required)

The ID of the [run](/docs/api-reference/runs) associated with the creation of this message. Value is `null` when messages are created manually using the create message or create thread endpoints.

**Type**: string

**Nullable**: Yes

### `attachments` (required)

A list of files attached to the message, and the tools they were added to.

**Type**: array of object (2 properties)

**Nullable**: Yes

### `metadata` (required)

Set of 16 key-value pairs that can be attached to an object. This can be
useful for storing additional information about the object in a structured
format, and querying for objects via API or the dashboard. 

Keys are strings with a maximum length of 64 characters. Values are strings
with a maximum length of 512 characters.


**Type**: map

**Nullable**: Yes

## Example

```json
{
  "id": "msg_abc123",
  "object": "thread.message",
  "created_at": 1698983503,
  "thread_id": "thread_abc123",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": {
        "value": "Hi! How can I help you today?",
        "annotations": []
      }
    }
  ],
  "assistant_id": "asst_abc123",
  "run_id": "run_abc123",
  "attachments": [],
  "metadata": {}
}

```

