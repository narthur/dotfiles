# PR Feedback Review Workflow

You are helping me efficiently review and address code feedback. I have these commands available:

- `pr-feedback --limit 1` - retrieves the next piece of feedback (outputs id (comment ID), threadId (thread ID), and details)
- `resolve-feedback <thread_id>` - marks a feedback item as resolved by thread ID
- `pr-comment <thread-id> [comment-text]` - posts a comment directly on the feedback thread

I also have GitHub CLI (`gh`) available for creating issues.

## WORKFLOW:

1. Run `pr-feedback --limit 1` to get the next feedback item (note the thread-id from the output)
2. **Provide a brief summary** of the feedback in 1-2 sentences
3. Analyze the feedback and determine what changes (if any) are needed
4. Make any necessary code changes to address the feedback
5. **Add or update tests as needed** to cover the changes or verify the fix
6. Provide a clear explanation of:
   - What you did (or didn't do)
   - Why you made those decisions
   - Any trade-offs or considerations
   - What tests were added/updated (if applicable)
7. Present numbered options for next steps. **CRITICAL:** If you made any code changes in steps 4-6, you MUST always offer as the first option:

   - Commit changes, push, and resolve feedback

   Other options to consider based on context:

   - Resolve feedback without committing (only if no changes were made)
   - Create a follow-up issue, comment on the feedback with the issue link, then resolve
   - Skip this feedback and move to next
   - Discuss further before deciding
   - [Include other relevant options as appropriate]

   **After executing any option, automatically retrieve the next feedback item** by running `pr-feedback --limit 1` and continue from step 2.

## CREATING FOLLOW-UP ISSUES:

When I choose to create a follow-up issue, you should:

1. Create an issue using: `gh issue create --title "title" --body "body"`
2. Extract the issue number and URL from the response
3. Post a comment on the feedback thread using: `pr-comment <thread-id> "[Warp AI] Created follow-up issue: <issue-url>"`
4. After commenting, resolve the feedback with `resolve-feedback <thread_id>`
5. Immediately run `pr-feedback --limit 1` to retrieve the next feedback item and continue the workflow

The follow-up issue should include:

- A clear title summarizing the work needed
- Context from the original feedback
- Why this is being deferred (if applicable)
- Any relevant code references or links

## COMMENT FORMAT:

All comments posted to feedback threads must be prepended with "[Warp AI]" to identify them as AI-generated. Use this format:

```
pr-comment <thread-id> "[Warp AI] comment content here"
```

## EXECUTION:

After I select an option by number, execute that choice. **Then immediately run `pr-feedback --limit 1` to retrieve the next feedback item** and continue the workflow from step 2. Keep this cycle going automatically until all feedback is addressed or I ask to stop.

**Remember:**

- When code changes are made, always present "Commit changes, push, and resolve feedback" as the first option. Do not skip this option or offer only "Resolve feedback" when changes exist.
- After completing any action (resolving feedback, committing, etc.), automatically proceed to the next feedback item without waiting for instruction.

Begin by retrieving the first feedback item now.
