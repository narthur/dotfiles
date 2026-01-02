# PR Feedback Review Workflow

You are helping me efficiently review and address code feedback. I have these commands available:

- `pr-feedback --limit 1` - retrieves the next piece of feedback (outputs feedback_id, thread_id, and details)
- `resolve-feedback <feedback_id>` - marks a feedback item as resolved
- `pr-comment <thread-id> [comment-text]` - posts a comment directly on the feedback thread

I also have GitHub CLI (`gh`) available for creating issues.

## WORKFLOW:

1. Run `pr-feedback --limit 1` to get the next feedback item (note the thread-id from the output)
2. **Provide a brief summary** of the feedback in 1-2 sentences
3. Analyze the feedback and determine what changes (if any) are needed
4. Make any necessary code changes to address the feedback
5. **Add or update tests as needed** to cover the changes or verify the fix
6. **Update WARP.md files** throughout the project to reflect:
   - New patterns or conventions learned from the feedback
   - Important decisions or trade-offs made
   - Architectural insights or design principles discovered
   - Any gotchas or pitfalls to avoid in related code
7. Provide a clear explanation of:
   - What you did (or didn't do)
   - Why you made those decisions
   - Any trade-offs or considerations
   - What tests were added/updated (if applicable)
   - What WARP.md updates were made (if applicable)
8. Present numbered options for next steps, such as:
   - Commit changes, push, and resolve feedback
   - Resolve feedback without committing (if no changes needed)
   - Create a follow-up issue, comment on the feedback with the issue link, then resolve
   - Skip this feedback and move to next
   - Discuss further before deciding
   - [Include other relevant options as appropriate]

## CREATING FOLLOW-UP ISSUES:

When I choose to create a follow-up issue, you should:

1. Create an issue using: `gh issue create --title "title" --body "body"`
2. Extract the issue number and URL from the response
3. Post a comment on the feedback thread using: `pr-comment <thread-id> "[Warp AI] Created follow-up issue: <issue-url>"`
4. After commenting, resolve the feedback with `resolve-feedback <feedback_id>`
5. Continue to the next feedback item

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

After I select an option by number, execute that choice and continue to the next feedback item. Keep this cycle going until all feedback is addressed or I ask to stop.

Begin by retrieving the first feedback item now.
