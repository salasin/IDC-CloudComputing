1. Do not forget to populate the keys in deploy.sh before running the stack.
2. The part that sets up the redis server is flaky. When running from a script it sometimes succeeds, and sometimes it
fails due to broken dependencies. It works every time when run manually. Simply rerunning the installation part
(lines 57-63) again fixes this too.