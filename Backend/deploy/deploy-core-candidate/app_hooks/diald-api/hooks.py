"""Proposed hooks: review/install in an immutable central deploy-core release."""
from pathlib import Path
from urllib.parse import quote
import tempfile
import deploy_core as core


def accept(image):
    core.compose('exec', '-T', 'diald-api', 'bun', 'deploy/verify.ts', image=image)


def prepare(candidate, current):
    core.backup_database('dialdclub')
    # Confirm the protected credential filename against the host inventory before
    # installing this candidate. Never read the API runtime password for migrations.
    secret = core.protected_file(core.APP.parents[1] / 'projects/dialdclub/owner-password', 'Migration credential')
    with tempfile.TemporaryDirectory(prefix='diald-owner-migration-') as folder:
        config = Path(folder) / 'migration.env'
        config.write_text('DATABASE_URL=postgresql://dialdclub_owner:' + quote(secret.read_text().strip(), safe='') + '@postgres:5432/dialdclub\n')
        config.chmod(0o600)
        core.run(['docker','run','--rm','--read-only','--cap-drop','ALL','--security-opt',
                  'no-new-privileges:true','--network','platform-db','--memory','256m',
                  '--cpus','0.5','--env-file',str(config),candidate,'bun','scripts/migrate.ts'])
