# Submission

Fork URL: <!-- paste the URL of your fork here -->

## Files to commit

- [ ] `notes.md` with your commands and what you saw (optional)

## Questions

Answer in your own words. Where a question asks for output, paste it in a code block.

### Q1. Paste the two failover records (primary and secondary) and the health check settings. What are the interval, the failure threshold and so the longest time before a failover?

**Your answer:**

<!-- replace this line with your answer -->

### Q2. Stop the primary and paste the answers of `aws route53 test-dns-answer` before and after. How long did the change take and what decided it?

**Your answer:**

<!-- replace this line with your answer -->

### Q3. What does the record TTL do to the clients that already looked the name up? Which two numbers add up to the real worst case?

**Your answer:**

<!-- replace this line with your answer -->

### Q4. Why can the health check not tell the difference between "the server is down" and "the health check endpoint is broken"? What did you serve at `/healthz`?

**Your answer:**

<!-- replace this line with your answer -->

### Q5. Failover routing, weighted routing and latency routing: pick the right one for (a) a blue/green cutover, (b) users in Europe and Asia, (c) a standby.

**Your answer:**

<!-- replace this line with your answer -->

### Q6. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.

**Your answer:**

<!-- replace this line with your answer -->

### Q7. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.

**Your answer:**

<!-- replace this line with your answer -->
