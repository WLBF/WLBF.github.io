# Windows Manifest
<!-- ---
title: Windows Manifest
date: 2018-03-12 22:57:43
tags: 日常
--- -->

最近用 rust 在 windows 上写安装程序，碰到了 PCA(Program Compatibility Assistant) 的问题，安装卸载的时候总是弹窗。msdn 上的有关 PCA 的文档写得不是很详细。后来对比了一下其他的安装程序发现问题出在 manifest 上，在 manifest 中加上 compatibility 字段就解决了。后来发现有个 stackoverflow 问题提到了这个解决方法，可惜没有早点搜到。最后 manifest 长这样：

``` xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="1.0.0.0" name="MyApplication.app"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
      <supportedOS Id="{35138b9a-5d96-4fbd-8e2d-a2440225f93a}"/>
    </application>
  </compatibility>
</assembly>
```

一些参考文档：
[Manifests](https://msdn.microsoft.com/en-us/library/windows/desktop/aa375365.aspx)
[Application Compatibility: Program Compatibility Assistant (PCA)](https://msdn.microsoft.com/en-us/library/bb756937.aspx)
[Reasons for getting the Program Compatibility Assistant dialog?](https://stackoverflow.com/questions/5098747/reasons-for-getting-the-program-compatibility-assistant-dialog)

还有一个需要解决的问题是 rustc 并不支持将 manifest 编译进 exe, 参考:

[https://github.com/rust-lang/rfcs/issues/721](https://github.com/rust-lang/rfcs/issues/721)

原本 msvc 是将 manifest 当做 rc 编译链接的，rustc 还没做这个功能，absolutely zero progress......，只能参考这个：
[How do I add a manifest to an executable using mt.exe?](https://stackoverflow.com/questions/1423492/how-do-i-add-a-manifest-to-an-executable-using-mt-exe)

用 win10 sdk 里的 mt.exe 把 manifest 塞进编好的 exe 中，在 CI 里加上一行：

``` text
mt.exe -nologo -manifest "c:\project\setup.exe.manifest" -outputresource:"c:\project\setup.exe;#1"
```