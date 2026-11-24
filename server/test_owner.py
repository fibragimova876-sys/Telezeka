import os, tempfile, unittest
from contextlib import closing
import server as s
class Permissions(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        s.DB=os.path.join(self.tmp.name,'test.db'); s.INVITE='test-invite'
        os.environ['TELEZEKA_OWNER_PASSWORD']='test-password-123456789'
        s.init(); s.init()
        self.owner=self.call('POST','/login',{'email':'zakaria@telezeka.local','password':'test-password-123456789'})
        self.member=self.call('POST','/register',{'name':'Member','username':'member1','email':'member@example.test','password':'member-test-password','invite':s.INVITE})
    def tearDown(self): self.tmp.cleanup()
    def call(self,method,path,body=None,token=''):
        with closing(s.db()) as c,c:
            return s.run(c,method,path,{},body or {},'Bearer '+token)
    def test_owner_and_member(self):
        self.assertEqual(self.owner['user']['role'],'owner')
        self.assertEqual(self.owner['user']['name'],'Закария')
        self.assertEqual(self.member['user']['role'],'member')
        with self.assertRaises(s.Err): self.call('GET','/admin/users',token=self.member['token'])
        self.call('POST','/admin/ban',{'uid':self.member['user']['id'],'banned':True},self.owner['token'])
        with self.assertRaises(s.Err): self.call('GET','/me',token=self.member['token'])
        with self.assertRaises(s.Err): self.call('POST','/admin/ban',{'uid':self.owner['user']['id']},self.owner['token'])
    def test_registration_and_private_chats(self):
        self.call('POST','/admin/settings',{'registration':'closed'},self.owner['token'])
        with self.assertRaises(s.Err): self.call('POST','/register',{'name':'Another','email':'another@example.test','password':'test-password','invite':s.INVITE})
        ch=self.call('POST','/chats',{'kind':'group','title':'Private'},self.member['token'])['id']
        with self.assertRaises(s.Err): self.call('GET',f'/chats/{ch}/messages',token=self.owner['token'])
        self.call('POST',f'/chats/{ch}/prefs',{'favorite':True},self.member['token'])
        self.assertEqual(self.call('GET','/chats',token=self.member['token'])[0]['favorite'],1)
if __name__=='__main__': unittest.main()
