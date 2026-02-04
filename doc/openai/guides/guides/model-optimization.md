Model optimization
==================

Ensure quality model outputs with evals and fine-tuning in the OpenAI platform.

LLM output is non-deterministic, and model behavior changes between model snapshots and families. Developers must constantly measure and tune the performance of LLM applications to ensure they're getting the best results. In this guide, we explore the techniques and OpenAI platform tools you can use to ensure high quality outputs from the model.

[

![Evals](https://cdn.openai.com/API/docs/images/blue_card.png)

Evals

Systematically measure performance.

](/docs/guides/evals)[

![Prompt engineering](https://cdn.openai.com/API/docs/images/orange_card.png)

Prompt engineering

Give context, instructions, and goals.

](/docs/guides/text?api-mode=responses#prompt-engineering)[

![Fine-tuning](https://cdn.openai.com/API/docs/images/purple_card.png)

Fine-tuning

Train models to excel at a task.

](/docs/guides/fine-tuning)

Model optimization workflow
---------------------------

Optimizing model output requires a combination of **evals**, **prompt engineering**, and **fine-tuning**, creating a flywheel of feedback that leads to better prompts and better training data for fine-tuning. The optimization process usually goes something like this.

1.  Write [evals](/docs/guides/evals) that measure model output, establishing a baseline for performance and accuracy.
2.  [Prompt the model](/docs/guides/text) for output, providing relevant context data and instructions.
3.  For some use cases, it may be desirable to [fine-tune](/docs/guides/fine-tuning) a model for a specific task.
4.  Run evals using test data that is representative of real world inputs. Measure the performance of your prompt and fine-tuned model.
5.  Tweak your prompt or fine-tuning dataset based on eval feedback.
6.  Repeat the loop continuously to improve your model results.

Here's an overview of the major steps, and how to do them using the OpenAI platform.

Build evals
-----------

In the OpenAI platform, you can [build and run evals](/docs/guides/evals) either via API or in the [dashboard](/evaluations). You might even consider writing evals _before_ you start writing prompts, taking an approach akin to behavior-driven development (BDD).

Run your evals against test inputs like you expect to see in production. Using one of several available [graders](/docs/guides/graders), measure the results of a prompt against your test data set.

[

Learn about evals

Run tests on your model outputs to ensure you're getting the right results.

](/docs/guides/evals)

Write effective prompts
-----------------------

With evals in place, you can effectively iterate on [prompts](/docs/guides/text). The prompt engineering process may be all you need in order to get great results for your use case. Different models may require different prompting techniques, but there are several best practices you can apply across the board to get better results.

*   **Include relevant context** - in your instructions, include text or image content that the model will need to generate a response from outside its training data. This could include data from private databases or current, up-to-the-minute information.
*   **Provide clear instructions** - your prompt should contain clear goals about what kind of output you want. GPT models like `gpt-4.1` are great at following very explicit instructions, while [reasoning models](/docs/guides/reasoning) like `o4-mini` tend to do better with high level guidance on outcomes.
*   **Provide example outputs** - give the model a few examples of correct output for a given prompt (a process called few-shot learning). The model can extrapolate from these examples how it should respond for other prompts.

[

Learn about prompt engineering

Learn the basics of writing good prompts for the model.

](/docs/guides/text)

Fine-tune a model
-----------------

Using the latest base [models](/docs/models) and iterating on prompts might be all you need to achieve good performance for your use case, but sometimes it's useful to [fine-tune a model](/docs/guides/fine-tuning) for a specific task. Fine-tuning exposes a model to additional training data that it can use to update its weights, and adjust how it responds to prompts.

Fine-tuning can be a time-consuming process, but it can also enable a model to consistently format responses in a certain way or handle novel inputs.

[

Learn about fine-tuning

Learn how to fine-tune a model for a specific use case.

](/docs/guides/fine-tuning)

Learn from experts
------------------

Model optimization is a complex topic, and sometimes more art than science. Check out the videos below from members of the OpenAI team on model optimization techniques.

Cost/accuracy/latency

Distillation

Optimizing LLM Performance