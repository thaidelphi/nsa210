# ZyXEL NSA210 Modernization & TLS 1.3 BitTorrent Tracker Proxy

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: ARMv5te](https://img.shields.io/badge/Platform-ARMv5te%20%28NSA210%29-blue.svg)]()
[![TLS 1.3](https://img.shields.io/badge/TLS-1.3%20Support-green.svg)]()
[![Transmission](https://img.shields.io/badge/Transmission-2.94-orange.svg)]()

ชุดอัปเกรดระบบและแพตช์สำหรับ **ZyXEL NSA210 (NAS)** เพื่อให้ใช้งาน BitTorrent (Transmission) ร่วมกับ Private Tracker ยุคใหม่ (SiamBIT, Bit-SV และ Tracker อื่นๆ ที่ใช้ Cloudflare / TLS 1.3) ได้อย่างสมบูรณ์แบบ พร้อมฟีเจอร์แก้ไข Tracker แบบ BitComet, ปรับแต่งหน้าเว็บคอนโทรล ZyXEL Web GUI, และเปิดแชร์ไฟล์ Samba สู่ Windows 10 / 11

---

## 📌 ที่มาและปัญหา (The Problem)

ZyXEL NSA210 เป็น NAS พลังงานต่ำ (CPU Marvell Kirkwood ARM926EJ-S ARMv5te, Linux Kernel 2.6.31.8) ซึ่งหยุดพัฒนาไปหลายปี:
1. **TLS 1.3 / Cloudflare:** ปัจจุบันเว็บ BitTorrent Tracker ส่วนใหญ่ (เช่น SiamBIT, Bit-SV) บังคับใช้ TLS 1.2/1.3 ร่วมกับระบบป้องกัน Cloudflare ทำให้ OpenSSL และ libcurl ดั้งเดิมบน NAS ไม่สามารถเชื่อมต่อ Announce ได้ (เกิดข้อผิดพลาด `Peer certificate cannot be authenticated` หรือ `Unsupported protocol`)
2. **Transmission ติดข้อจำกัด HTTPS:** Transmission ดั้งเดิมบน NSA210 ไม่รองรับการเชื่อมต่อ HTTPS Tracker สมัยใหม่
3. **การแก้ไข Tracker:** Transmission ดั้งเดิมไม่มีหน้าต่างสำหรับแก้ไขหรือใส่ลิสต์ Tracker หลายรายการพร้อมกันได้อย่างสะดวกเหมือนบนโปรแกรม BitComet
4. **ZyXEL Web GUI ยุคเก่า:** หน้าเว็บ ZyXEL ดั้งเดิมเขียนด้วย Dojo ยุคเก่า เมื่อเปิดหน้า Transmission มักเด้งเป็นหน้าต่างใหม่ (Popup) หรือติดรหัสผ่านของ Apache
5. **แชร์ไฟล์บน Windows 10/11 ไม่ได้:** Samba ดั้งเดิมไม่รองรับการเข้าถึงแบบ Guest ของ Windows ยุคใหม่

---

## ✨ คุณสมบัติหลัก (Key Features)

### 1. TLS 1.3 & Cloudflare Tracker Proxy Daemon (`tracker_proxy.pl`)
- **Forwarder Proxy ในตัว:** รันบน `127.0.0.1:8888` ทำหน้าที่รับ Announce request จาก Transmission แล้วส่งต่อผ่าน `curl-8.14` แบบ TLS 1.3 ไปยัง Tracker จริง
- **Static curl 8.14 (ARMv5te, musl, OpenSSL 3.5.0):** ไบนารีคอมไพล์แบบ Static พิเศษสำหรับชิป ARMv5 ไม่พึ่งพา glibc/uClibc รุ่นเก่าของระบบ
- **DNS Cache & Cloudflare Anycast:** แก้ปัญหา DNS timeout บน NAS ด้วยการแมป IP ตรง (`--resolve host:443:ip`)
- **รองรับ Disabled Tracker:** ระบบจำลองการตอบกลับเพื่อรองรับการพัก Tracker ได้อย่างราบรื่นโดยไม่เกิดข้อผิดพลาดกับ Transmission Daemon
- **Auto-Patching Loop:** สแกนตรวจสอบ Torrent ที่เพิ่งเพิ่มเข้ามาใหม่ทุก 30 วินาที และแปลง HTTPS Tracker ผ่าน Proxy ให้อัตโนมัติ

### 2. Transmission Web UI - เครื่องมือแก้ไข Tracker สไตล์ BitComet
- **ปุ่ม [ ✏️ แก้ Tracker (BitComet) ] บน Toolbar** และเมนูคลิกขวา (Context Menu)
- **เครื่องมือจัดการ URL Tracker:** เพิ่ม/แก้ไขรายการ Tracker ทีละหลายบรรทัดได้สะดวกเหมือนโปรแกรม BitComet บน PC
- **เลือกลิสต์ Torrent ได้จาก Dropdown** ภายในกล่อง Popup ทันที
- **บันทึกแบบ Sequential RPC:** เรียก `trackerAdd` ก่อนแล้วตามด้วย `trackerRemove` เพื่อขจัดบั๊ก `Transmission RPC: invalid argument`
- **ระบบสำรองข้อมูลใน LocalStorage:** จำค่า Tracker ที่แก้ไขไว้แม้รีเฟรชหน้าเว็บ

### 3. ปรับปรุง ZyXEL Web Admin Integration
- หน้าเว็บ Transmission ฝังเนียนตาใน **Applications -> Transmission**
- แสดงสถานะการทำงาน `● ออนไลน์ Online (Port 9091)`
- ปุ่มทางลัด `↗ เปิด Transmission ในแท็บใหม่ (Full Tab)`
- แก้ไขเมนูฝั่งซ้าย (`frame_left_menu.html`) ให้เปิด Transmission ในกรอบขวาโดยตรง **ไม่เด้ง Tab/Popup ใหม่กวนใจ** และเมนูอื่นๆ (Storage, Users, Network, Maintenance) ยังคงทำงานได้ตามปกติ 100%
- ปรับแต่ง Apache (`AuthZyxelSkipPattern`) เพื่อให้เข้าหน้าเว็บได้ทันทีโดยไม่ต้องล็อกอินซ้ำซ้อน

### 4. Samba Shares เข้าได้จาก Windows 10 / 11
- กำหนดสิทธิ์ Anonymous / Guest ให้เข้าถึงโฟลเดอร์ดาวน์โหลดได้โดยตรง:
  - `\\<IP-NAS>\download`
  - `\\<IP-NAS>\Transmission`
- สิทธิ์การเขียนไฟล์เต็มรูปแบบ (`write ok = yes`, `force user = root`, `create mask = 0777`)
- อ่านคู่มือการแก้ปัญหาและการตั้งค่าสำหรับ Windows 11 ได้ที่: [docs/WINDOWS_11_SMB_SETUP.md](docs/WINDOWS_11_SMB_SETUP.md)

### 5. ระบบบูตอัตโนมัติ (Persistent Boot Hooks)
- ตั้งค่าให้ทุกเซอร์วิส (DNS, Tracker Proxy, Transmission Daemon, Bind Mount เมนูเว็บ, Apache Auth) เริ่มทำงานเองอัตโนมัติทุกครั้งที่เปิดหรือรีบูตเครื่อง NAS ผ่าน `/usr/local/zy-pkgs/etc/init.d/sshd`

---

## 📂 โครงสร้างไฟล์ใน Repository (Project Structure)

```text
nsa210/
├── bin/
│   ├── curl-8.14                   # Static curl 8.14.1 (ARMv5te, musl, OpenSSL 3.5.0, TLS 1.3)
│   └── tracker_proxy.pl            # Perl daemon สำหรับแปลง request TLS 1.3 และจัดการ tracker
├── docs/
│   └── WINDOWS_11_SMB_SETUP.md     # คู่มือการตั้งค่าและแก้ปัญหาการเชื่อมต่อ SMB บน Windows 11 (24H2)
├── transmission/
│   ├── web/
│   │   ├── index.html              # Transmission Web Interface ที่เพิ่ม Toolbar & Modal Editor
│   │   └── javascript/
│   │       └── transmission.js     # JavaScript ควบคุม BitComet Tracker Editor & Sequential RPC
│   └── config/
│       └── settings.json           # Template ค่าคอนฟิกเริ่มต้นของ Transmission Daemon
├── zyxel-web/
│   ├── pkg/
│   │   └── Transmission/
│   │       └── index.html          # หน้า Wrapper ควบคุม Transmission ในระบบ ZyXEL Web Admin
│   └── admin/
│       └── frame_left_menu.html    # แพตช์เมนูด้านซ้ายของ ZyXEL Admin Portal
├── samba/
│   ├── connect_nsa210.bat          # สคริปต์คลิกเดียวสำหรับเชื่อมต่อและเปิดไดรฟ์ U: (Windows)
│   ├── fix_smb_windows11.bat       # สคริปต์แก้ปัญหาการเชื่อมต่อ Samba บน Windows 11 (24H2)
│   └── smb.conf                    # คอนฟิก Samba สำหรับแชร์ไฟล์สู่ Windows 10/11
├── init.d/
│   └── sshd                        # สคริปต์ Startup Hook เริ่มการทำงานของระบบอัตโนมัติเมื่อบูต
├── install.sh                      # สคริปต์ติดตั้งระบบทั้งหมดแบบอัตโนมัติ
├── .gitignore
└── README.md
```

---

## 🚀 วิธีการติดตั้ง (Installation)

### ข้อกำหนดเบื้องต้น (Prerequisites)
1. ZyXEL NSA210 ที่ลงแพ็กเกจ FFP (fonfunplug) และเปิดใช้งาน SSH แล้ว
2. ติดตั้งแพ็กเกจ `Transmission` ผ่าน ZyXEL Package Management
3. สิทธิ์การใช้งาน Root

### ขั้นตอนการติดตั้ง

1. เชื่อมต่อเข้าไปยัง NSA210 ผ่าน SSH:
   ```bash
   ssh root@<IP_NAS>
   ```

2. ดาวน์โหลดโปรเจกต์จาก GitHub:
   ```bash
   cd /tmp
   git clone https://github.com/thaidelphi/nsa210.git
   cd nsa210
   ```
   *(หรือคัดลอกไฟล์ขึ้นไปยัง NAS ผ่าน scp / WinSCP)*

3. รันสคริปต์ติดตั้ง:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

4. สคริปต์จะทำการ:
   - ติดตั้ง `curl-8.14` และ `tracker_proxy.pl` ไปยัง `/usr/local/zy-pkgs/bin/`
   - ปรับแต่งหน้าเว็บ Transmission และ Web Portal
   - เชื่อมต่อ Mount เมนูด้านซ้ายของ ZyXEL Portal
   - อัปเดตคอนฟิก Samba ให้ Windows 10/11 เข้าถึงได้
   - เริ่มต้นการทำงานของ Tracker Proxy และ Transmission

---

## 💻 การเข้าใช้งาน (Usage)

- **Transmission Web UI แบบเต็มหน้าจอ:**
  ```text
  http://<IP_NAS>:9091/transmission/web/
  ```
- **ZyXEL Web Portal:**
  ```text
  http://<IP_NAS>/
  เข้าสู่เมนู Applications -> Transmission
  ```
- **การเข้าโฟลเดอร์ไฟล์ดาวน์โหลดบน Windows:**
  ```text
  \\<IP_NAS>\download
  \\<IP_NAS>\Transmission
  ```

### วิธีใช้งานเครื่องมือแก้ Tracker (BitComet Style)
1. เปิดหน้าเว็บ Transmission แล้วคลิกปุ่มสีเขียว **[ ✏️ แก้ Tracker (BitComet) ]** ด้านบน
2. เลือกรายการ Torrent ที่ต้องการแก้ไขจากเมนูดรอปดาวน์
3. คัดลอกหรือแก้ไขลิสต์ URL Tracker ตามที่ต้องการ (รองรับการใส่หลายบรรทัด)
4. กดปุ่ม **Save (บันทึก)** ระบบจะทำการบันทึกและเชื่อมต่อ Tracker ให้ทันที

---

## 🛡️ License

MIT License - พัฒนาและเผยแพร่เพื่อให้เป็นประโยชน์ต่อผู้ใช้งาน ZyXEL NSA Series ทุกท่าน
