# Shape shared by the scheduled background LaunchAgents (restic, maintenance).
# Not RunAtLoad: these are calendar jobs, and firing them all at every login is exactly
# the thundering herd the schedule exists to avoid.
{
  program,
  schedule,
  nice ? 10,
  # ProcessType "Background" hands the job to a resource band macOS is free to throttle and
  # eventually kill. That is fine for a job that finishes in a minute, and wrong for one that
  # streams gigabytes: the Mac's restic run started dying with "signal terminated received"
  # on 2026-08-14, the day its set grew by ~10GB, after months of finishing in ~90s.
  # "Standard" keeps the low IO priority and the nice value but stops the reaping.
  longRunning ? false,
}:
{
  enable = true;
  config = {
    ProgramArguments = [ program ];
    StartCalendarInterval = schedule;
    RunAtLoad = false;
    ProcessType = if longRunning then "Standard" else "Background";
    LowPriorityIO = true;
    Nice = nice;
  };
}
