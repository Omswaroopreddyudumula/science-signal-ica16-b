import subprocess as s,time,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
adb=str(Path.home()/'Library/Android/sdk/platform-tools/adb');pkg='com.campusdesk.science_signal_16'
def sh(*args):return s.run([adb,'shell',*args],capture_output=True,text=True)
def flag(name):return sh('run-as',pkg,'test','-f','cache/ica16-'+name).returncode==0
def mark(name):sh('run-as',pkg,'touch','cache/ica16-'+name)
records=[]
def record(event):records.append({'event':event,'timestamp':__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat()})
try:
 deadline=time.monotonic()+150
 while not flag('off-request'):
  if time.monotonic()>deadline:raise RuntimeError('No offline test request received')
  time.sleep(.3)
 sh('svc','wifi','disable');sh('svc','data','disable');time.sleep(1)
 connectivity=sh('dumpsys','connectivity').stdout
 active=next((line.strip() for line in connectivity.splitlines() if 'Active default network:' in line),'not reported')
 record('Wi-Fi and mobile data disabled; '+active);mark('off-confirmed')
 deadline=time.monotonic()+35
 while not flag('on-request'):
  if time.monotonic()>deadline:raise RuntimeError('Offline safety limit reached')
  time.sleep(.3)
 sh('svc','wifi','enable');sh('svc','data','enable');time.sleep(2);record('Wi-Fi and mobile data restored');mark('on-confirmed')
 print('Actual device networking disabled and restored for T08.',flush=True)
finally:
 sh('svc','wifi','enable');sh('svc','data','enable')
 (root/'evidence/T08-device-network-control.json').write_text(json.dumps(records,indent=2))
