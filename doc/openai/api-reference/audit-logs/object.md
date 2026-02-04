# The audit log object

A log of a user action or configuration change within this organization.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The ID of this log. |
| `type` | string | Yes |  | `api_key.created`, `api_key.updated`, `api_key.deleted`, `checkpoint_permission.created`, `checkpoint_permission.deleted`, `invite.sent`, `invite.accepted`, `invite.deleted`, `login.succeeded`, `login.failed`, `logout.succeeded`, `logout.failed`, `organization.updated`, `project.created`, `project.updated`, `project.archived`, `service_account.created`, `service_account.updated`, `service_account.deleted`, `rate_limit.updated`, `rate_limit.deleted`, `user.added`, `user.updated`, `user.deleted` | The event type. |
| `effective_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of the event. |
| `project` | object (2 properties) | No |  |  | The project that the action was scoped to. Absent for actions not scoped to projects. |
| `actor` | object (3 properties) | Yes |  |  | The actor who performed the audit logged action. |
|   ↳ `api_key` | object (4 properties) | No |  |  | The API Key used to perform the audit logged action. |
|     ↳ `user` | object (2 properties) | No |  |  | The user who performed the audit logged action. |
|     ↳ `service_account` | object (1 property) | No |  |  | The service account that performed the audit logged action. |
| `api_key.created` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `api_key.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `api_key.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `checkpoint_permission.created` | object (2 properties) | No |  |  | The project and fine-tuned model checkpoint that the checkpoint permission was created for. |
| `checkpoint_permission.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `invite.sent` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `invite.accepted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `invite.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `login.failed` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `logout.failed` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `organization.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
|     ↳ `name` | string | No |  |  | The organization name. |
|     ↳ `settings` | object (2 properties) | No |  |  |  |
| `project.created` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `project.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `project.archived` | object (1 property) | No |  |  | The details for events with this `type`. |
| `rate_limit.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
|     ↳ `max_images_per_1_minute` | integer | No |  |  | The maximum images per minute. Only relevant for certain models. |
|     ↳ `max_audio_megabytes_per_1_minute` | integer | No |  |  | The maximum audio megabytes per minute. Only relevant for certain models. |
|     ↳ `max_requests_per_1_day` | integer | No |  |  | The maximum requests per day. Only relevant for certain models. |
|     ↳ `batch_1_day_max_input_tokens` | integer | No |  |  | The maximum batch input tokens per day. Only relevant for certain models. |
| `rate_limit.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `service_account.created` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `service_account.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `service_account.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `user.added` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `user.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `user.deleted` | object (1 property) | No |  |  | The details for events with this `type`. |
| `certificate.created` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `certificate.updated` | object (2 properties) | No |  |  | The details for events with this `type`. |
| `certificate.deleted` | object (3 properties) | No |  |  | The details for events with this `type`. |
|   ↳ `certificate` | string | No |  |  | The certificate content in PEM format. |
| `certificates.activated` | object (1 property) | No |  |  | The details for events with this `type`. |

### Items in `certificates` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | No |  |  | The certificate ID. |
| `name` | string | No |  |  | The name of the certificate. |
| `certificates.deactivated` | object (1 property) | No |  |  | The details for events with this `type`. |

### Items in `certificates` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | No |  |  | The certificate ID. |
| `name` | string | No |  |  | The name of the certificate. |

## Property Details

### `id` (required)

The ID of this log.

**Type**: string

### `type` (required)

The event type.

**Type**: string

**Allowed values**: `api_key.created`, `api_key.updated`, `api_key.deleted`, `checkpoint_permission.created`, `checkpoint_permission.deleted`, `invite.sent`, `invite.accepted`, `invite.deleted`, `login.succeeded`, `login.failed`, `logout.succeeded`, `logout.failed`, `organization.updated`, `project.created`, `project.updated`, `project.archived`, `service_account.created`, `service_account.updated`, `service_account.deleted`, `rate_limit.updated`, `rate_limit.deleted`, `user.added`, `user.updated`, `user.deleted`

### `effective_at` (required)

The Unix timestamp (in seconds) of the event.

**Type**: integer

### `project`

The project that the action was scoped to. Absent for actions not scoped to projects.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `name`

### `actor` (required)

The actor who performed the audit logged action.

**Type**: object (3 properties)

**Nested Properties**:

* `type`, `session`, `api_key`

### `api_key.created`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `data`

### `api_key.updated`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `changes_requested`

### `api_key.deleted`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `id`

### `checkpoint_permission.created`

The project and fine-tuned model checkpoint that the checkpoint permission was created for.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `data`

### `checkpoint_permission.deleted`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `id`

### `invite.sent`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `data`

### `invite.accepted`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `id`

### `invite.deleted`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `id`

### `login.failed`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `error_code`, `error_message`

### `logout.failed`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `error_code`, `error_message`

### `organization.updated`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `changes_requested`

### `project.created`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `data`

### `project.updated`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `changes_requested`

### `project.archived`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `id`

### `rate_limit.updated`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `changes_requested`

### `rate_limit.deleted`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `id`

### `service_account.created`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `data`

### `service_account.updated`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `changes_requested`

### `service_account.deleted`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `id`

### `user.added`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `data`

### `user.updated`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `changes_requested`

### `user.deleted`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `id`

### `certificate.created`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `name`

### `certificate.updated`

The details for events with this `type`.

**Type**: object (2 properties)

**Nested Properties**:

* `id`, `name`

### `certificate.deleted`

The details for events with this `type`.

**Type**: object (3 properties)

**Nested Properties**:

* `id`, `name`, `certificate`

### `certificates.activated`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `certificates`

### `certificates.deactivated`

The details for events with this `type`.

**Type**: object (1 property)

**Nested Properties**:

* `certificates`

## Example

```json
{
    "id": "req_xxx_20240101",
    "type": "api_key.created",
    "effective_at": 1720804090,
    "actor": {
        "type": "session",
        "session": {
            "user": {
                "id": "user-xxx",
                "email": "user@example.com"
            },
            "ip_address": "127.0.0.1",
            "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        }
    },
    "api_key.created": {
        "id": "key_xxxx",
        "data": {
            "scopes": ["resource.operation"]
        }
    }
}

```

