-- PowerSync streams changes from Postgres via logical replication and needs a
-- publication containing the app tables that should reach offline clients.

drop publication if exists powersync;

create publication powersync for table
  public.profiles,
  public.beans,
  public.brew_sessions,
  public.brew_steps,
  public.brew_reminders;
