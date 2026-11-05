"""Local HTTP MCP client fallback when the desktop tool attachment times out."""
import argparse
import base64
import json
from pathlib import Path
import urllib.request


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('operation',choices=['list','describe','call'])
    parser.add_argument('name',nargs='?')
    parser.add_argument('--args-file',type=Path)
    parser.add_argument('--image-output',type=Path)
    args=parser.parse_args()
    session=None
    def request(method,params=None,notification=False):
        nonlocal session
        payload={'jsonrpc':'2.0','method':method}
        if not notification: payload['id']=1
        if params is not None: payload['params']=params
        headers={'Content-Type':'application/json','Accept':'application/json, text/event-stream','MCP-Protocol-Version':'2025-03-26'}
        if session: headers['Mcp-Session-Id']=session
        req=urllib.request.Request('http://127.0.0.1:8000/mcp',json.dumps(payload).encode(),headers)
        with urllib.request.urlopen(req,timeout=50) as response:
            session=response.headers.get('Mcp-Session-Id',session)
            raw=response.read().decode()
        if not raw.strip(): return {}
        if raw.startswith('event:') or raw.startswith('data:'):
            raw=next(line[5:].strip() for line in raw.splitlines() if line.startswith('data:') and '"result"' in line)
        data=json.loads(raw)
        if 'error' in data: raise RuntimeError(data['error'])
        return data.get('result',{})
    request('initialize',{'protocolVersion':'2025-03-26','capabilities':{},'clientInfo':{'name':'polygon-lab-validation','version':'1'}})
    request('notifications/initialized',notification=True)
    if args.operation in ('list','describe'):
        result=request('tools/list')
        Path('tmp/godot_mcp_tools.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        if args.operation=='list': print(json.dumps([t['name'] for t in result['tools']]))
        else: print(json.dumps(next(t for t in result['tools'] if t['name']==args.name),ensure_ascii=False))
    else:
        result=request('tools/call',{'name':args.name,'arguments':json.loads(args.args_file.read_text(encoding='utf-8-sig')) if args.args_file else {}})
        output=[]
        for block in result.get('content',[]):
            if block['type']=='image':
                if args.image_output:
                    args.image_output.parent.mkdir(parents=True,exist_ok=True)
                    args.image_output.write_bytes(base64.b64decode(block['data']))
                    output.append({'image_saved':str(args.image_output)})
            elif block['type']=='text':
                try: output.append(json.loads(block['text']))
                except ValueError: output.append(block['text'])
        print(json.dumps(output,ensure_ascii=False))
        if result.get('isError'): raise SystemExit(1)


if __name__=='__main__': main()
