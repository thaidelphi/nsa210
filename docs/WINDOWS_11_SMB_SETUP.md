# คู่มือการตั้งค่า Samba (SMB) บน Windows 11 เพื่อเชื่อมต่อ ZyXEL NSA210

เอกสารนี้รวบรวมสาเหตุของปัญหาและขั้นตอนการแก้ปัญหาการเชื่อมต่อแชร์ไดรฟ์เน็ตเวิร์ก (`\\<IP_NAS>\download`) จาก **Windows 11 (24H2)** ไปยัง **ZyXEL NSA210** อย่างละเอียด

---

## 📌 1. สาเหตุของปัญหา (The Problem)

ZyXEL NSA210 ใช้ระบบแชร์ไฟล์ **Samba 3.0.35** ซึ่งรองรับเฉพาะโปรโตคอล **SMB 1.0 (SMBv1 / NT LM 0.12)** ดั้งเดิมเท่านั้น

เมื่อเชื่อมต่อจาก **Windows 11 (โดยเฉพาะเวอร์ชัน 24H2 / Build 26100+)** จะพบปัญหาเข้าไม่ได้ (ติด `System error 64` หรือ `System error 53`) เนื่องจาก Microsoft ได้เพิ่มระบบความปลอดภัยใหม่ 3 ด้าน:

1. **SMB 1.0 ถูกปิดไว้เป็นค่าเริ่มต้น:** Windows รุ่นใหม่จะไม่ติดตั้งไดรเวอร์ SMB 1.0 มาให้ตั้งแต่ต้น
2. **บังคับใช้ SMB Client Mandatory Signing (`RequireSecuritySignature = True`):** Windows 11 บังคับให้การเชื่อมต่อ SMB ทุกประเภทต้องมีการเข้ารหัส Signing ซึ่ง Samba 3.0 รุ่นเก่าไม่รองรับ ทำให้ Windows ตัดการเชื่อมต่อทันที (`System error 64: The specified network name is no longer available`)
3. **บล็อก Insecure Guest Logons (`EnableInsecureGuestLogons = False`):** Windows 11 ไม่อนุญาตให้เชื่อมต่อแชร์โฟลเดอร์แบบ Guest ที่ไม่มีการใส่รหัสผ่าน

---

## 🛠️ 2. ขั้นตอนการตั้งค่าฝั่ง Windows 11

### วิธีที่ 1: ใช้สคริปต์อัตโนมัติ (ง่ายและเร็วที่สุด)
รันไฟล์ **`fix_smb_windows11.bat`** (หรือ `fix_smb.bat` บน Desktop) ด้วยการ:
1. คลิกขวาที่ไฟล์ -> เลือก **Run as administrator**
2. กด **Yes** ที่หน้าต่างยืนยันสิทธิ์ UAC
3. ทำการ **Restart คอมพิวเตอร์ 1 ครั้ง**

---

### วิธีที่ 2: ตั้งค่าด้วยตัวเองผ่านคำสั่ง

#### ขั้นตอนที่ 2.1: เปิดฟีเจอร์ SMB 1.0 Client
1. กดปุ่ม `Windows + R` พิมพ์ `optionalfeatures` แล้วกด Enter
2. เลื่อนหาหัวข้อ **SMB 1.0/CIFS File Sharing Support**
3. ติ๊กถูกที่ช่อง:
   - `[✓] SMB 1.0/CIFS Client`
4. กด **OK** รอระบบติดตั้งไฟล์

#### ขั้นตอนที่ 2.2: ปลดล็อกความปลอดภัย Windows 11 ผ่าน PowerShell
คลิกขวาที่ปุ่ม Start -> เลือก **Terminal (Admin)** หรือ **PowerShell (Admin)** แล้วคัดลอกคำสั่งต่อไปนี้ไปวาง:

```powershell
# 1. อนุญาตให้เข้าถึงแชร์โฟลเดอร์แบบ Guest (ไม่ต้องใส่รหัสผ่าน)
Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Confirm:$false

# 2. ปิดการบังคับ SMB Signing ที่บล็อก NAS รุ่นเก่า
Set-SmbClientConfiguration -RequireSecuritySignature $false -Confirm:$false

# 3. ตั้งค่า Registry เพิ่มเติมเพื่อความเสถียร
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v RequireSecuritySignature /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v EnableSecuritySignature /t REG_DWORD /d 0 /f

# 4. รีสตาร์ทเซอร์วิส Workstation
Restart-Service LanmanWorkstation -Force
```

#### ขั้นตอนที่ 2.3: รีสตาร์ทคอมพิวเตอร์ 1 ครั้ง (จำเป็นอย่างยิ่ง!)
> ⚠️ **สำคัญมาก:** หลังจากเปิด SMB 1.0 แล้ว จะต้อง **Restart คอมพิวเตอร์ 1 ครั้ง** เสมอ เพื่อให้ Windows Kernel โหลดไดรเวอร์ `mrxsmb10.sys` เข้าสู่หน่วยความจำ หากไม่รีสตาร์ทจะไม่สามารถเชื่อมต่อ SMB1 ได้

---

## 🖥️ 3. ขั้นตอนการตั้งค่าฝั่ง NAS (ZyXEL NSA210)

แก้ไขไฟล์คอนฟิก Samba บน NAS ที่ `/etc/samba/smb.conf`:

```ini
[global]
	workgroup = WORKGROUP
	server string = NSA210
	netbios name = nsa210
	dos charset = UTF8
	display charset = UTF8
	unix charset = UTF8
	security = user
	lanman auth = yes
	ntlm auth = yes
	server signing = auto
	encrypt passwords = yes
	smb passwd file = /etc/samba/smbpasswd
	guest account = pc-guest
	map to guest = Bad User
	write ok = yes
	force create mode = 777
	force directory mode = 777

[download]
	comment = Transmission Downloads
	path = /i-data/md0/admin/download
	public = yes
	guest ok = yes
	browseable = yes
	writable = yes
	write ok = yes
	force user = root
	create mask = 0777
	directory mask = 0777

[Transmission]
	comment = Transmission Finished Torrents
	path = /i-data/md0/admin/download/Transmission
	public = yes
	guest ok = yes
	browseable = yes
	writable = yes
	write ok = yes
	force user = root
	create mask = 0777
	directory mask = 0777
```

บันทึกไฟล์แล้วสั่งโหลดคอนฟิกใหม่บน NAS:
```bash
killall -HUP smbd
```

---

## 🔗 4. การเชื่อมต่อและ Map Network Drive บน Windows

เมื่อตั้งค่าทั้ง 2 ฝั่งและรีสตาร์ทคอมพิวเตอร์เรียบร้อยแล้ว:

### วิธีเชื่อมต่อเป็นไดรฟ์ถาวร (เช่น ไดรฟ์ U:)
เปิด Command Prompt หรือ PowerShell แล้วรันคำสั่ง:
```cmd
net use U: \\192.168.1.69\download /persistent:yes
```

- พารามิเตอร์ `/persistent:yes` จะทำให้ไดรฟ์ `U:` คงอยู่ถาวร แม้เปิดเครื่องคอมพิวเตอร์ใหม่ก็เข้าใช้งานได้ทันที
- สามารถเข้าผ่าน **This PC** -> ดับเบิ้ลคลิกไดรฟ์ **`download (U:)`** ได้ทันที

### การเข้าผ่าน File Explorer โดยตรง
พิมพ์ในช่อง Address bar ของ File Explorer:
```text
\\192.168.1.69\download
```
หรือ
```text
\\192.168.1.69
```

---

## ❓ 5. ตรวจสอบและแก้ปัญหา (Troubleshooting)

### ตรวจสอบว่าไดรเวอร์ SMB 1.0 ทำงานอยู่หรือไม่
เปิด CMD / PowerShell แล้วรัน:
```cmd
sc query mrxsmb10
```
- หากขึ้น `STATE : 4 RUNNING` แปลว่าไดรเวอร์ SMB1 ทำงานเรียบร้อย
- หากขึ้น `FAILED 1060: The specified service does not exist` แปลว่ายังไม่ได้เปิด SMB 1.0 หรือยังไม่ได้รีสตาร์ทคอมพิวเตอร์

### ตรวจสอบสถานะการเชื่อมต่อ Network Drive
```cmd
net use
```
- จะแสดงรายการไดรฟ์ทั้งหมด หากสถานะเป็น `OK` แสดงว่าเชื่อมต่อสมบูรณ์
