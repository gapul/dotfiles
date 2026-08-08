# Shape shared by the scheduled background LaunchAgents (restic, maintenance).
# Not RunAtLoad: these are calendar jobs, and firing them all at every login is exactly
# the thundering herd the schedule exists to avoid.
{
  program,
  schedule,
  nice ? 10,
}:
{
  enable = true;
  config = {
    ProgramArguments = [ program ];
    StartCalendarInterval = schedule;
    RunAtLoad = false;
    ProcessType = "Background";
    LowPriorityIO = true;
    Nice = nice;
  };
}
