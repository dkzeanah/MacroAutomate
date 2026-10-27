# Rebuild the standalone browser guide from its authoritative Markdown source.
# Requires PowerShell 7's built-in ConvertFrom-Markdown; no network/dependencies.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$guideSourcePath = Join-Path $PSScriptRoot 'AUTOMATION_USER_GUIDE.md'
$guideOutputPath = Join-Path $PSScriptRoot 'AUTOMATION_USER_GUIDE.html'
$guideBodyHtml = (ConvertFrom-Markdown -LiteralPath $guideSourcePath).Html
# Markdig strips a leading chapter number from heading IDs; preserve Markdown's
# numbered anchors so the static contents links also work without JavaScript.
$guideBodyHtml = [regex]::Replace($guideBodyHtml, '<h2 id="([^"]+)">(\d+)\. ', {
    param($guideHeadingMatch)
    '<h2 id="' + $guideHeadingMatch.Groups[2].Value + '-' + $guideHeadingMatch.Groups[1].Value + '">' + $guideHeadingMatch.Groups[2].Value + '. '
})
$guideTemplate = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Macro Automator · Automation Guide</title>
<style>
:root{color-scheme:light dark;--bg:#f5f7fa;--panel:#fff;--ink:#172436;--muted:#506179;--line:#d8e1ec;--accent:#0757a0;--code:#edf2f8}
@media(prefers-color-scheme:dark){:root{--bg:#111923;--panel:#192432;--ink:#e5edf6;--muted:#a6b7cd;--line:#354557;--accent:#8ec7ff;--code:#243447}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.65 system-ui,Segoe UI,sans-serif}
header{position:sticky;top:0;z-index:2;background:var(--panel);border-bottom:1px solid var(--line);padding:14px 24px;display:flex;align-items:center;gap:20px;flex-wrap:wrap}
header strong{font-size:18px}header label{display:flex;align-items:center;gap:10px;flex:1;min-width:240px}
input{width:100%;max-width:500px;border:1px solid var(--line);border-radius:6px;padding:9px 12px;background:var(--bg);color:var(--ink);font:inherit}
button{border:1px solid var(--line);border-radius:6px;padding:9px 14px;color:var(--ink);background:var(--bg);cursor:pointer;font:inherit}
.layout{display:grid;grid-template-columns:280px minmax(0,1000px);gap:26px;max-width:1350px;margin:auto;padding:28px 20px}
aside{position:sticky;top:100px;height:calc(100vh - 125px);overflow:auto;padding:0 12px 20px 0}aside p{color:var(--muted);font-size:13px;margin-top:0}
nav a{display:block;padding:8px 10px;border-radius:5px;font-size:14px;line-height:1.4;text-decoration:none}nav a:hover{background:var(--code)}
main{min-width:0;background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:30px 36px}
h1{font-size:32px;line-height:1.2;margin:0 0 22px}h2{font-size:24px;line-height:1.35;margin-top:0}h3{font-size:19px;margin:28px 0 10px}
section{padding:30px 0;border-top:1px solid var(--line);scroll-margin-top:110px}p{margin:12px 0}a{color:var(--accent)}
table{display:block;overflow:auto;border-collapse:collapse;width:100%;margin:20px 0;font-size:14px}th,td{padding:10px 12px;border:1px solid var(--line);text-align:left;vertical-align:top}th{background:var(--code)}
pre{overflow:auto;padding:18px;border:1px solid var(--line);border-radius:6px;background:var(--code);line-height:1.55}code{font:13px/1.5 Consolas,monospace;background:var(--code);border-radius:3px;padding:2px 4px}pre code{padding:0}
li{margin:7px 0}img{max-width:100%}[hidden]{display:none!important}#results,#empty{color:var(--muted)}#empty{padding:24px 0}
@media(max-width:900px){header{position:static}.layout{grid-template-columns:1fr}aside{position:static;height:auto;max-height:230px}main{padding:22px 18px}section{scroll-margin-top:15px}h1{font-size:27px}}
@media print{header,aside,#empty{display:none}.layout{display:block;padding:0}main{border:0;padding:0;background:white;color:black}section[hidden]{display:block!important}table{display:table;font-size:10px}pre{white-space:pre-wrap}a{color:black}}
</style>
</head>
<body>
<header><strong>Macro Automator · Guide</strong><label for="search">Search <input id="search" type="search" placeholder="Try spools, OCR, shortcuts, DeepSeek…" autocomplete="off"></label><button id="clear" type="button">Clear</button><button id="print" type="button">Print / PDF</button></header>
<div class="layout"><aside aria-label="Guide navigation"><p>Code-backed reference · 6 October 2026<br>66 actions · 19 tabs · practical sequences</p><p id="results" role="status" aria-live="polite"></p><nav id="chapters"></nav></aside><main id="guide">
<!--GUIDE_BODY-->
<p id="empty" hidden>No matching chapters. Try another term or clear the search.</p>
</main></div>
<script>
const main=document.querySelector('#guide'),nav=document.querySelector('#chapters'),search=document.querySelector('#search');
let section=null;const chapters=[];
// Remove the Markdown TOC because the browser guide supplies persistent navigation.
let removeToc=false;
for(const node of Array.from(main.children)){
  if(node.tagName==='H2'&&node.textContent.trim()==='Contents'){removeToc=true;node.remove();continue;}
  if(removeToc&&node.tagName!=='H2'){node.remove();continue;}
  if(node.tagName==='H2'){
    removeToc=false;
    section=document.createElement('section');main.insertBefore(section,node);
    const anchor=node.id||node.textContent.toLowerCase().replace(/[^a-z0-9\s-]/g,'').trim().replace(/\s+/g,'-');
    section.id=anchor;node.removeAttribute('id');
    const link=document.createElement('a');link.href='#'+anchor;link.textContent=node.textContent;nav.append(link);
    chapters.push({section,link,text:''});
  }
  if(section&&node.id!=='empty')section.append(node);
}
for(const chapter of chapters)chapter.text=chapter.section.textContent.toLowerCase();
function filter(){
  const query=search.value.toLowerCase().trim();let visible=0;
  for(const chapter of chapters){const match=!query||chapter.text.includes(query);chapter.section.hidden=!match;chapter.link.hidden=!match;if(match)visible++;}
  document.querySelector('#results').textContent=query?visible+' of '+chapters.length+' chapters match':chapters.length+' chapters · select a topic below';
  document.querySelector('#empty').hidden=visible>0;
}
search.addEventListener('input',filter);
document.querySelector('#clear').addEventListener('click',()=>{search.value='';filter();search.focus();});
document.querySelector('#print').addEventListener('click',()=>window.print());
filter();
</script>
</body></html>
'@
[IO.File]::WriteAllText($guideOutputPath, $guideTemplate.Replace('<!--GUIDE_BODY-->', $guideBodyHtml), [Text.UTF8Encoding]::new($false))
Write-Output "Built $guideOutputPath"
