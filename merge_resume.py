import os
from pypdf import PdfReader, PdfWriter
from PIL import Image

files = [
    r'C:\Users\Don\Desktop\.pdf\DonovanZeanahResume.pdf',
    r'C:\Users\Don\Desktop\.pdf\driverlicense.pdf',
    r'C:\Users\Don\Desktop\.pdf\Gmail - Score Report Available Notification.pdf',
    r'C:\Users\Don\Desktop\.pdf\Software Development- Score Report.pdf',
    r'C:\Users\Don\Desktop\.pdf\spacetec-cert.jpg',
    r'C:\Users\Don\Desktop\.pdf\ATLTech.pdf',
]
out_path = r'C:\Users\Don\Desktop\.pdf\DonovanZeanahResume-Combined.pdf'

writer = PdfWriter()
report = []
for f in files:
    if not os.path.exists(f):
        report.append('MISSING: ' + f)
        continue
    low = f.lower()
    if low.endswith('.jpg') or low.endswith('.jpeg') or low.endswith('.png'):
        img = Image.open(f)
        if img.mode != 'RGB':
            img = img.convert('RGB')
        tmp = f + '.tmp.pdf'
        img.save(tmp, 'PDF', resolution=100.0)
        r = PdfReader(tmp)
        for p in r.pages:
            writer.add_page(p)
        os.remove(tmp)
        report.append('IMG->PDF ok: ' + f)
    else:
        r = PdfReader(f)
        for p in r.pages:
            writer.add_page(p)
        report.append('PDF ok: ' + f + ' (' + str(len(r.pages)) + ' pages)')

with open(out_path, 'wb') as fh:
    writer.write(fh)
print('OUTPUT:', out_path)
print('TOTAL PAGES:', len(writer.pages))
for rline in report:
    print(rline)
