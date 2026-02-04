# Costs object

The aggregated costs details of the specific time bucket.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.costs.result` |  |
| `amount` | object (2 properties) | No |  |  | The monetary value in its associated currency. |
| `line_item` | string | No |  |  | When `group_by=line_item`, this field provides the line item of the grouped costs result. |
| `project_id` | string | No |  |  | When `group_by=project_id`, this field provides the project ID of the grouped costs result. |

## Property Details

### `object` (required)

**Type**: string

**Allowed values**: `organization.costs.result`

### `amount`

The monetary value in its associated currency.

**Type**: object (2 properties)

**Nested Properties**:

* `value`, `currency`

### `line_item`

When `group_by=line_item`, this field provides the line item of the grouped costs result.

**Type**: string

**Nullable**: Yes

### `project_id`

When `group_by=project_id`, this field provides the project ID of the grouped costs result.

**Type**: string

**Nullable**: Yes

## Example

```json
{
    "object": "organization.costs.result",
    "amount": {
      "value": 0.06,
      "currency": "usd"
    },
    "line_item": "Image models",
    "project_id": "proj_abc"
}

```

