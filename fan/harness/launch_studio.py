"""Launch the independent Python toolkit located alongside the Fan application."""
import argparse
from pathlib import Path
from studio.app import StudioApp

parser = argparse.ArgumentParser()
parser.add_argument('--tab', default='index', choices=['index','atlas','automation','guide','gate','harness','ingest','condense','coagulate','ledger','create','export'])
parser.add_argument('--query-hex', default='')
args = parser.parse_args()
app = StudioApp(Path(__file__).resolve().parent)
app.select_tab(args.tab)
if args.query_hex:
    app.tabs['index'].search.set(bytes.fromhex(args.query_hex).decode('utf-8'))
    app.tabs['index'].refresh_symbols()
app.mainloop()
