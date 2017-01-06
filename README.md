# LeetTracker (Alpha)

<a href="https://github.com/yuhuili">![Yuhui Li](https://githubtools.yuhuili.com/kagami/yuhuili/Yuhui%20Li/)</a>

<img src="GitHub/ss1.png" width="400">

LeetTracker automatically fetches all of your LeetCode submissions to your GitHub repository. It is written purely in Swift and runs on macOS. Check out the [demo repository](https://github.com/yuhuili/LeetTrackerDemo), or try this [precompiled version](https://github.com/yuhuili/LeetTracker-Release/raw/master/GitHub/LeetTracker.zip).

## Features
- Submissions are organized into individual problems
- README for each problem that includes problem description and submission details
- LeetTracker remembers which submissions have been cached and will not fetch them again

## Known Issues
- Start button will not be re-enabled after the process is completed.

## Note
- Git Repo Dir: the absolute path to a valid local git folder
- Database Dir: any blank file
- LC Cookie: Cookie associated with an active LeetCode session

## To-do
- Add direct login
- Finish implementing completion handlers so Start button can be resetted when process completes
- Replace hacky booleans with DispatchQueue
- Generate initial database file
- Automatic commit with detailed logging messages for each scan and commit
- Error handling and retries in case of network failure
