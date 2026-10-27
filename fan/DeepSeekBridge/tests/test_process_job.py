"""Owned process cleanup; no GUI/input or API request is involved."""
import os
import subprocess
import sys
import pytest


@pytest.mark.skipif(os.name != 'nt', reason='Windows job object contract')
def test_job_close_stops_owned_process():
    from bridge.process_job import ProcessJob
    process = subprocess.Popen([getattr(sys, '_base_executable', sys.executable), '-c', 'import time; time.sleep(30)'],
                               creationflags=subprocess.CREATE_NO_WINDOW)
    job = ProcessJob()
    try:
        job.add(process)
        assert process.poll() is None
        job.close()
        # Windows can report zero when a job closes. The contract is that the
        # owned sleeper exits within five seconds, well before its 30s sleep.
        process.wait(timeout=5)
        assert process.poll() is not None
    finally:
        job.close()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
