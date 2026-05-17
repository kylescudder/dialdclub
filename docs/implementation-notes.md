# Implementation Notes

- Deadwax Club main was pulled before starting this repo.
- Lottie spinner support was kept as a first-class component.
- Deletions are implemented as deleted_at updates, not hard deletes.
- The backend creates profile rows from email, Apple, and Google signup metadata.
- The app uses local notifications immediately and uploads APNs tokens for later Supabase Edge Function fan-out.
- The Supabase Edge Function is deliberately a minimal fan-out hook until real APNs credentials are available.
