#!/usr/bin/env python3
import base64
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / 'Scripts/build_update_feed.py'
spec = importlib.util.spec_from_file_location('feed_builder', SCRIPT)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

class BuilderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='systemeq-feed-tests-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root/'app'
        (self.app/'Contents').mkdir(parents=True)
        self.info = {'CFBundleShortVersionString':'1.4.5','CFBundleVersion':'7','SUFeedURL':builder.FEED_URL,
                     'SUPublicEDKey':base64.b64encode(bytes(32)).decode(),'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True}
        self.save_info()
        (self.root/'Config').mkdir()
        (self.root/'Config/Info.plist').write_bytes(plistlib.dumps(self.info))
        self.archive = self.root/'SystemEQ-v1.4.5.zip'
        self.archive.write_bytes(b'archive fixture')
        self.notes = self.root/'notes.txt';self.notes.write_text('Release notes')
        self.output = self.root/'appcast.xml'
        self.tools = self.root/'tools';(self.tools/'bin').mkdir(parents=True)
        script = self.tools/'bin/generate_appcast'
        script.write_text('''#!/usr/bin/env python3
import os,pathlib,sys
assert 'SPARKLE_ED25519_PRIVATE_KEY' not in os.environ
key=sys.stdin.readline().strip()
assert key and key not in sys.argv
root=pathlib.Path.cwd()
(root/'generator-called').write_text('yes')
mode=os.environ.get('FEED_TEST_MODE','')
if mode=='command-fail': print(key,file=sys.stderr);sys.exit(7)
if mode=='mutate-archive':
 p=next(root.glob('*.zip'));p.write_bytes(b'changed')
if mode!='missing-feed': (root/'appcast.xml').write_text('<fixture/>')
''')
        script.chmod(0o755)
        self.bin = self.root/'bin';self.bin.mkdir()
        validator = self.bin/'swift'
        validator.write_text('''#!/usr/bin/env python3
import os,pathlib,sys
assert 'SPARKLE_ED25519_PRIVATE_KEY' not in os.environ
sys.exit(7 if os.environ.get('FEED_TEST_MODE')=='verify-fail' or not pathlib.Path(sys.argv[2]).is_file() else 0)
''')
        validator.chmod(0o755)
        self.key = base64.b64encode(bytes(range(32))).decode()
        self.env = dict(os.environ, SPARKLE_ED25519_PRIVATE_KEY=self.key, PATH=str(self.bin)+os.pathsep+os.environ['PATH'])
        self.root_patch = patch.object(builder,'ROOT',self.root);self.root_patch.start();self.addCleanup(self.root_patch.stop)

    def save_info(self):
        (self.app/'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))

    def invoke(self, mode='', module=builder):
        with patch.dict(os.environ,dict(self.env,FEED_TEST_MODE=mode),clear=True):
            module.generate(self.app,self.archive,self.tools,self.output,'1.4.5',self.notes)

    def test_healthy_transport_uses_stdin_and_no_private_environment(self):
        self.invoke()
        self.assertTrue(self.output.is_file())
        for log in self.root.rglob('*.log'):
            self.assertNotIn(self.key,log.read_text())

    def test_bad_metadata_and_keys_fail_before_generator(self):
        for field,value in [('CFBundleVersion','0'),('CFBundleShortVersionString','1.0.0'),('SUPublicEDKey','wrong'),('SURequireSignedFeed',False),('SUVerifyUpdateBeforeExtraction',False)]:
            with self.subTest(field=field):
                previous=self.info[field];self.info[field]=value;self.save_info()
                with self.assertRaises(RuntimeError): self.invoke()
                self.info[field]=previous;self.save_info()
                self.assertFalse(list(self.root.rglob('generator-called')))
        for value in ('','bad',base64.b64encode(b'short').decode()):
            self.env['SPARKLE_ED25519_PRIVATE_KEY']=value
            with self.assertRaises((RuntimeError,ValueError)): self.invoke()
            self.assertFalse(list(self.root.rglob('generator-called')))

    def test_existing_and_symlink_output_are_preserved(self):
        self.output.write_bytes(b'preserve')
        with self.assertRaises(RuntimeError): self.invoke()
        self.assertEqual(self.output.read_bytes(),b'preserve')
        self.output.unlink();target=self.root/'user-data';target.write_bytes(b'preserve')
        self.output.symlink_to(target)
        with self.assertRaises(RuntimeError): self.invoke()
        self.assertEqual(target.read_bytes(),b'preserve')

    def test_feed_read_failure_does_not_create_output(self):
        original = Path.read_bytes
        def read(path):
            if path.name == 'appcast.xml': raise OSError('Read failed')
            return original(path)
        with patch.object(Path,'read_bytes',read):
            with self.assertRaises(OSError): self.invoke()
        self.assertFalse(self.output.exists())

    def test_partial_staged_write_does_not_create_output(self):
        original = Path.open
        class PartialWrite:
            def __init__(self,stream): self.stream=stream
            def __enter__(self): return self
            def __exit__(self,*args): self.stream.close()
            def write(self,data):
                self.stream.write(data[:2]);self.stream.flush()
                raise OSError('Write failed')
        def open_file(path,*args,**kwargs):
            stream=original(path,*args,**kwargs)
            if path.name=='verified-appcast.xml' and args==('xb',): return PartialWrite(stream)
            return stream
        with patch.object(Path,'open',open_file):
            with self.assertRaises(OSError): self.invoke()
        self.assertFalse(self.output.exists())
        self.assertEqual(next(self.root.rglob('verified-appcast.xml')).read_bytes(),b'<f')

    def test_atomic_publication_failure_and_existing_file_race(self):
        with patch.object(builder.os,'link',side_effect=OSError('Link failed')):
            with self.assertRaises(OSError): self.invoke()
        self.assertFalse(self.output.exists())
        def race(source,destination):
            self.output.write_bytes(b'preserve racing file')
            raise FileExistsError('Output appeared')
        with patch.object(builder.os,'link',side_effect=race):
            with self.assertRaises(FileExistsError): self.invoke()
        self.assertEqual(self.output.read_bytes(),b'preserve racing file')

    def test_generator_failure_redacts_and_cannot_publish(self):
        with self.assertRaises(RuntimeError): self.invoke('command-fail')
        self.assertFalse(self.output.exists())
        logs=list(self.root.rglob('generation.log'));self.assertEqual(len(logs),1)
        self.assertNotIn(self.key,logs[0].read_text());self.assertIn('<redacted>',logs[0].read_text())

    def test_timeout_is_redacted_and_cannot_publish(self):
        with patch('subprocess.run',side_effect=subprocess.TimeoutExpired(['generator'],1,output=self.key.encode())):
            with self.assertRaises(RuntimeError): self.invoke()
        self.assertFalse(self.output.exists())
        self.assertNotIn(self.key,next(self.root.rglob('generation.log')).read_text())

    def test_missing_feed_mutated_archive_and_failed_verifier_cannot_publish(self):
        for mode in ('missing-feed','mutate-archive','verify-fail'):
            with self.subTest(mode=mode):
                with self.assertRaises(RuntimeError): self.invoke(mode)
                self.assertFalse(self.output.exists())
                self.assertEqual(self.archive.read_bytes(),b'archive fixture')

    def test_known_bad_verification_bypass_is_caught(self):
        source=SCRIPT.read_text().replace("require(checked.returncode == 0, 'Signed appcast validation failed')","require(True, 'Signed appcast validation failed')")
        self.assertNotEqual(source,SCRIPT.read_text())
        mutant=types.ModuleType('mutant');mutant.__file__=str(SCRIPT)
        exec(compile(source,'mutant.py','exec'),mutant.__dict__);mutant.ROOT=self.root
        def validation():
            with self.assertRaises(RuntimeError): self.invoke('verify-fail',module=mutant)
        with self.assertRaises(AssertionError): validation()

@unittest.skipUnless(sys.platform=='darwin' and shutil.which('swiftc'),'CryptoKit integration requires macOS Swift')
class SignedFeedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='systemeq-feed-crypto-');cls.root=Path(cls.temp.name)
        cls.generator=cls.root/'generator';cls.verifier=cls.root/'verifier'
        source=cls.root/'generate.swift'
        source.write_text(r'''import Foundation
import CryptoKit
let directory=URL(fileURLWithPath:CommandLine.arguments[1])
let mode=CommandLine.arguments[2]
let key=try Curve25519.Signing.PrivateKey(rawRepresentation:Data(repeating:1,count:32))
let archive=Data("fixture archive".utf8)
let signature=try key.signature(for:archive).base64EncodedString()
var xml="""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>7</sparkle:version><sparkle:shortVersionString>1.4.5</sparkle:shortVersionString><enclosure url="https://github.com/denzam/SystemEQ-for-Mac/releases/download/v1.4.5/SystemEQ-v1.4.5.zip" length="\(archive.count)" sparkle:edSignature="\(signature)"/></item></channel></rss>
"""
if mode=="wrong-build" {xml=xml.replacingOccurrences(of:">7<",with:">8<")}
if mode=="wrong-url" {xml=xml.replacingOccurrences(of:"https://github.com/",with:"https://example.invalid/")}
if mode=="bad-archive-signature" {xml=xml.replacingOccurrences(of:signature,with:Data(repeating:0,count:64).base64EncodedString())}
if mode=="external-notes" {xml=xml.replacingOccurrences(of:"</item>",with:"<sparkle:releaseNotesLink>https://example.invalid</sparkle:releaseNotesLink></item>")}
if mode=="deltas" {xml=xml.replacingOccurrences(of:"</item>",with:"<sparkle:deltas/></item>")}
if mode=="doctype" {xml=xml.replacingOccurrences(of:"<rss",with:"<!DOCTYPE rss><rss")}
let content=Data(xml.utf8)
let feedSignature=try key.signature(for:content).base64EncodedString()
var feed=content
if mode != "unsigned" {feed.append(Data("<!-- sparkle-signatures:\nedSignature: \(feedSignature)\nlength: \(content.count + (mode == "wrong-length" ? 1 : 0))\n-->\n".utf8))}
if mode=="corrupt-feed" {feed[10] ^= 1}
if mode=="trailing-junk" {feed.append(Data("extra".utf8))}
try feed.write(to:directory.appendingPathComponent("appcast.xml"))
try (mode=="corrupt-archive" ? archive+Data([0]) : archive).write(to:directory.appendingPathComponent("archive.zip"))
try key.publicKey.rawRepresentation.base64EncodedString().write(to:directory.appendingPathComponent("public.txt"),atomically:true,encoding:.utf8)
''')
        subprocess.run(['swiftc',str(source),'-o',str(cls.generator)],check=True,capture_output=True,timeout=90)
        subprocess.run(['swiftc',str(ROOT/'Scripts/verify_update_feed.swift'),'-o',str(cls.verifier)],check=True,capture_output=True,timeout=90)

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def check(self,mode):
        with tempfile.TemporaryDirectory(dir=self.root) as folder:
            path=Path(folder)
            subprocess.run([str(self.generator),folder,mode],check=True,capture_output=True,timeout=30)
            return subprocess.run([str(self.verifier),str(path/'appcast.xml'),str(path/'archive.zip'),(path/'public.txt').read_text(),
                'https://github.com/denzam/SystemEQ-for-Mac/releases/download/v1.4.5/SystemEQ-v1.4.5.zip','7','1.4.5'],capture_output=True,timeout=30)

    def test_signed_feed_and_archive_control(self): self.assertEqual(self.check('healthy').returncode,0)

    def test_corrupt_unsigned_untrusted_metadata_and_external_content_are_rejected(self):
        for mode in ('corrupt-feed','corrupt-archive','unsigned','wrong-build','wrong-url','bad-archive-signature','wrong-length','external-notes','deltas','doctype','trailing-junk'):
            with self.subTest(mode=mode): self.assertNotEqual(self.check(mode).returncode,0)

if __name__=='__main__': unittest.main()
