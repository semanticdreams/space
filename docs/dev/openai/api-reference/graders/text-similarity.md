# Text Similarity Grader

A TextSimilarityGrader object which grades text based on similarity metrics.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `type` | string | Yes | `text_similarity` | `text_similarity` | The type of grader. |
| `name` | string | Yes |  |  | The name of the grader. |
| `input` | string | Yes |  |  | The text being graded. |
| `reference` | string | Yes |  |  | The text being graded against. |
| `evaluation_metric` | string | Yes |  | `fuzzy_match`, `bleu`, `gleu`, `meteor`, `rouge_1`, `rouge_2`, `rouge_3`, `rouge_4`, `rouge_5`, `rouge_l` | The evaluation metric to use. One of `fuzzy_match`, `bleu`, `gleu`, `meteor`, `rouge_1`, `rouge_2`, `rouge_3`, `rouge_4`, `rouge_5`, or `rouge_l`. |

## Property Details

### `type` (required)

The type of grader.

**Type**: string

**Allowed values**: `text_similarity`

### `name` (required)

The name of the grader.

**Type**: string

### `input` (required)

The text being graded.

**Type**: string

### `reference` (required)

The text being graded against.

**Type**: string

### `evaluation_metric` (required)

The evaluation metric to use. One of `fuzzy_match`, `bleu`, `gleu`, `meteor`, `rouge_1`, `rouge_2`, `rouge_3`, `rouge_4`, `rouge_5`, or `rouge_l`.

**Type**: string

**Allowed values**: `fuzzy_match`, `bleu`, `gleu`, `meteor`, `rouge_1`, `rouge_2`, `rouge_3`, `rouge_4`, `rouge_5`, `rouge_l`

## Example

```json
{
  "type": "text_similarity",
  "name": "Example text similarity grader",
  "input": "{{sample.output_text}}",
  "reference": "{{item.label}}",
  "evaluation_metric": "fuzzy_match"
}

```

