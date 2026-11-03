---
title: Local setup
kind: runbook
---

# Local setup

1. Clone the repository and `cd` into it.
2. `bundle install`
3. `bundle exec rake test`
4. Run the dump against the dummy app:

   ```sh
   cd test/dummy
   RAILS_ENV=development bin/rails db:prepare
   bin/rails rails_vis:dump
   ```

5. Open `test/dummy/doc/rails_vis/index.html` in a browser.
