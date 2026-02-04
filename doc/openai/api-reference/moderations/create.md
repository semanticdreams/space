# Create moderation

`POST` `/moderations`

Classifies if text and/or image inputs are potentially harmful. Learn
more in the [moderation guide](/docs/guides/moderation).


## Request Body

### Content Type: `application/json`

**Type**: object (2 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `input` | oneOf: string | array of string | array of oneOf: object (2 properties) | object (2 properties) | Yes |  |  | Input (or inputs) to classify. Can be a single string, an array of strings, or <br> an array of multi-modal input objects similar to other models. <br>  |
| `model` | anyOf: string | string | No | `omni-moderation-latest` |  | The content moderation model you would like to use. Learn more in <br> [the moderation guide](/docs/guides/moderation), and learn about <br> available models [here](/docs/models#moderation). <br>  |
## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

Represents if a given text input is potentially harmful.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The unique identifier for the moderation request. |
| `model` | string | Yes |  |  | The model used to generate the moderation results. |
| `results` | array of object (4 properties) | Yes |  |  | A list of moderation objects. |


### Items in `results` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `flagged` | boolean | Yes |  |  | Whether any of the below categories are flagged. |
| `categories` | object (13 properties) | Yes |  |  | A list of the categories, and whether they are flagged or not. |
|   ↳ `harassment` | boolean | Yes |  |  | Content that expresses, incites, or promotes harassing language towards any target. |
|   ↳ `harassment/threatening` | boolean | Yes |  |  | Harassment content that also includes violence or serious harm towards any target. |
|   ↳ `illicit` | boolean | Yes |  |  | Content that includes instructions or advice that facilitate the planning or execution of wrongdoing, or that gives advice or instruction on how to commit illicit acts. For example, "how to shoplift" would fit this category. |
|   ↳ `illicit/violent` | boolean | Yes |  |  | Content that includes instructions or advice that facilitate the planning or execution of wrongdoing that also includes violence, or that gives advice or instruction on the procurement of any weapon. |
|   ↳ `self-harm` | boolean | Yes |  |  | Content that promotes, encourages, or depicts acts of self-harm, such as suicide, cutting, and eating disorders. |
|   ↳ `self-harm/intent` | boolean | Yes |  |  | Content where the speaker expresses that they are engaging or intend to engage in acts of self-harm, such as suicide, cutting, and eating disorders. |
|   ↳ `self-harm/instructions` | boolean | Yes |  |  | Content that encourages performing acts of self-harm, such as suicide, cutting, and eating disorders, or that gives instructions or advice on how to commit such acts. |
|   ↳ `sexual` | boolean | Yes |  |  | Content meant to arouse sexual excitement, such as the description of sexual activity, or that promotes sexual services (excluding sex education and wellness). |
|   ↳ `sexual/minors` | boolean | Yes |  |  | Sexual content that includes an individual who is under 18 years old. |
|   ↳ `violence` | boolean | Yes |  |  | Content that depicts death, violence, or physical injury. |
|   ↳ `violence/graphic` | boolean | Yes |  |  | Content that depicts death, violence, or physical injury in graphic detail. |
| `category_scores` | object (13 properties) | Yes |  |  | A list of the categories along with their scores as predicted by model. |
|   ↳ `harassment` | number | Yes |  |  | The score for the category 'harassment'. |
|   ↳ `harassment/threatening` | number | Yes |  |  | The score for the category 'harassment/threatening'. |
|   ↳ `illicit` | number | Yes |  |  | The score for the category 'illicit'. |
|   ↳ `illicit/violent` | number | Yes |  |  | The score for the category 'illicit/violent'. |
|   ↳ `self-harm` | number | Yes |  |  | The score for the category 'self-harm'. |
|   ↳ `self-harm/intent` | number | Yes |  |  | The score for the category 'self-harm/intent'. |
|   ↳ `self-harm/instructions` | number | Yes |  |  | The score for the category 'self-harm/instructions'. |
|   ↳ `sexual` | number | Yes |  |  | The score for the category 'sexual'. |
|   ↳ `sexual/minors` | number | Yes |  |  | The score for the category 'sexual/minors'. |
|   ↳ `violence` | number | Yes |  |  | The score for the category 'violence'. |
|   ↳ `violence/graphic` | number | Yes |  |  | The score for the category 'violence/graphic'. |
| `category_applied_input_types` | object (13 properties) | Yes |  |  | A list of the categories along with the input type(s) that the score applies to. |
|   ↳ `harassment` | array of string | Yes |  |  | The applied input type(s) for the category 'harassment'. |
|   ↳ `harassment/threatening` | array of string | Yes |  |  | The applied input type(s) for the category 'harassment/threatening'. |
|   ↳ `illicit` | array of string | Yes |  |  | The applied input type(s) for the category 'illicit'. |
|   ↳ `illicit/violent` | array of string | Yes |  |  | The applied input type(s) for the category 'illicit/violent'. |
|   ↳ `self-harm` | array of string | Yes |  |  | The applied input type(s) for the category 'self-harm'. |
|   ↳ `self-harm/intent` | array of string | Yes |  |  | The applied input type(s) for the category 'self-harm/intent'. |
|   ↳ `self-harm/instructions` | array of string | Yes |  |  | The applied input type(s) for the category 'self-harm/instructions'. |
|   ↳ `sexual` | array of string | Yes |  |  | The applied input type(s) for the category 'sexual'. |
|   ↳ `sexual/minors` | array of string | Yes |  |  | The applied input type(s) for the category 'sexual/minors'. |
|   ↳ `violence` | array of string | Yes |  |  | The applied input type(s) for the category 'violence'. |
|   ↳ `violence/graphic` | array of string | Yes |  |  | The applied input type(s) for the category 'violence/graphic'. |


### Items in `hate` array

Each item is of type `string`. Allowed values: `text`



### Items in `hate/threatening` array

Each item is of type `string`. Allowed values: `text`



### Items in `harassment` array

Each item is of type `string`. Allowed values: `text`



### Items in `harassment/threatening` array

Each item is of type `string`. Allowed values: `text`



### Items in `illicit` array

Each item is of type `string`. Allowed values: `text`



### Items in `illicit/violent` array

Each item is of type `string`. Allowed values: `text`



### Items in `self-harm` array

Each item is of type `string`. Allowed values: `text`, `image`



### Items in `self-harm/intent` array

Each item is of type `string`. Allowed values: `text`, `image`



### Items in `self-harm/instructions` array

Each item is of type `string`. Allowed values: `text`, `image`



### Items in `sexual` array

Each item is of type `string`. Allowed values: `text`, `image`



### Items in `sexual/minors` array

Each item is of type `string`. Allowed values: `text`



### Items in `violence` array

Each item is of type `string`. Allowed values: `text`, `image`



### Items in `violence/graphic` array

Each item is of type `string`. Allowed values: `text`, `image`

**Example:**

```json
{
  "id": "modr-0d9740456c391e43c445bf0f010940c7",
  "model": "omni-moderation-latest",
  "results": [
    {
      "flagged": true,
      "categories": {
        "harassment": true,
        "harassment/threatening": true,
        "sexual": false,
        "hate": false,
        "hate/threatening": false,
        "illicit": false,
        "illicit/violent": false,
        "self-harm/intent": false,
        "self-harm/instructions": false,
        "self-harm": false,
        "sexual/minors": false,
        "violence": true,
        "violence/graphic": true
      },
      "category_scores": {
        "harassment": 0.8189693396524255,
        "harassment/threatening": 0.804985420696006,
        "sexual": 1.573112165348997e-6,
        "hate": 0.007562942636942845,
        "hate/threatening": 0.004208854591835476,
        "illicit": 0.030535955153511665,
        "illicit/violent": 0.008925306722380033,
        "self-harm/intent": 0.00023023930975076432,
        "self-harm/instructions": 0.0002293869201073356,
        "self-harm": 0.012598046106750154,
        "sexual/minors": 2.212566909570261e-8,
        "violence": 0.9999992735124786,
        "violence/graphic": 0.843064871157054
      },
      "category_applied_input_types": {
        "harassment": [
          "text"
        ],
        "harassment/threatening": [
          "text"
        ],
        "sexual": [
          "text",
          "image"
        ],
        "hate": [
          "text"
        ],
        "hate/threatening": [
          "text"
        ],
        "illicit": [
          "text"
        ],
        "illicit/violent": [
          "text"
        ],
        "self-harm/intent": [
          "text",
          "image"
        ],
        "self-harm/instructions": [
          "text",
          "image"
        ],
        "self-harm": [
          "text",
          "image"
        ],
        "sexual/minors": [
          "text"
        ],
        "violence": [
          "text",
          "image"
        ],
        "violence/graphic": [
          "text",
          "image"
        ]
      }
    }
  ]
}

```

## Examples

