# Rust Which
<!-- ---
title: Rust Which
date: 2018-03-18 21:02:48
tags:
--- -->
在 windows 上 rust 标准库里的 `Command::spawn` 在寻找可执行文件的问题上有一些奇怪的问题，详见 issue:
[https://github.com/rust-lang/rust/issues/37519](https://github.com/rust-lang/rust/issues/37519)

issue 里提到干脆用先用 [which](https://github.com/fangyuanziti/which-rs) 这个库寻找绝对路径，然后在使用绝对路径调用子进程。在 windows 上 whcih 没有实现除了 exe 之外其他 `%PATHEXT%` 环境变量中指定的可执行文件后缀名。最近帮 which 实现了这个 feature。windows 平台上具体逻辑是： 如果路径后缀名已经是 `%PATHEXT%` 中规定的可执行文件，就不做任何处理，去相对路径，绝对路径，或 `%PATH%` 中规定的路径中寻找。如果没有后缀名或后缀名不属于 `%PATHEXT%` 就尝试给路径补上 `%PATHEXT%` 中的后缀名，然后再去寻找。

详见：[https://github.com/fangyuanziti/which-rs/pull/8](https://github.com/fangyuanziti/which-rs/pull/8)