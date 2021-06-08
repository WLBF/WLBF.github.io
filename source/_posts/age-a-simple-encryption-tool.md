---
title: age - A simple encryption tool
date: 2021-04-10 02:29:09
tags: cryptography
---
## Introduction

[age](https://github.com/FiloSottile/age) 是 Actual Good Encryption 的缩写, 是一个简单的现代文件加密工具。类似 GPG 通过非对称与对称加密技术实现文本信息的加密解密功能。age 定义了一种新的密文格式，并且使用了比较现代的加密算法，具体是 x25519 椭圆曲线算法和 chacha20poly1305 aead 算法。GitHub 上也已经有了对应的 rust 实现 [str4d/rage](https://github.com/str4d/rage)。

## Usage

age 的使用非常简单。通常情况下 x25519 曲线的公私钥二进制长度均为 32 个字节，在这里公私钥编码方式选择源自 Bitcoin 的 bech32。

```plaintext
➜  age git:(master) ✗ ./age-keygen 
# created: 2021-04-10T02:54:30+08:00
# public key: age1vm2yf505x5ctzw73vftk5gwzdsry4jlxfqhltsh4yfl07n6qluzsd8r9hk
AGE-SECRET-KEY-1Q4GC3VNU9HSKFFTJ5UTTDUXQGH9X6UQ0E3W53WT70QQLF57QR5RQF5CG53
➜  age git:(master) ✗ head -c 32 /dev/random | base64 > plain.txt
➜  age git:(master) ✗ ./age -r age1vm2yf505x5ctzw73vftk5gwzdsry4jlxfqhltsh4yfl07n6qluzsd8r9hk -o cipher.txt plain.txt
➜  age git:(master) ✗ ./age -i ./key.txt -o decrypt.txt -d chiper.txt
```

### ECDHE

ECDH 是一种利用椭圆曲线离散对数难题设计的密钥共享算法。可以简单描述为以下形式，a 和 b 为 alice 和 bob 的私钥，一般是两个随机数， a 和 b 分别与同一个基点 G 做乘法得到各自的公钥， 由于离散对数难题，傍观者无法通过公钥 A 和基点 G 计算出私钥。alice 和 bob 只需要使用自己的私钥和对方的公钥做乘法，即可得到双方共享的密钥。私钥可以选择临时生成，因为可能在完成了密钥交换之后，私钥就可能不再需要使用，ECDHE 最后一个字母 E 代表 ephemeral。

```plaintext
alice: A = aG
bob:   B = bG

Ab == abG == baG == Ba
```

下面是 golang curve25519 示例：

```golang
ephemeralA := make([]byte, curve25519.ScalarSize)
rand.Read(ephemeral)
publicKeyA, err := curve25519.X25519(ephemeralA, curve25519.Basepoint)

ephemeralB := make([]byte, curve25519.ScalarSize)
rand.Read(ephemeral)
publicKeyB, err := curve25519.X25519(ephemeralB, curve25519.Basepoint)

// sharedSecret1 == sharedSecret2
sharedSecret1, err := curve25519.X25519(ephemeralA, publicKeyB)
sharedSecret2, err := curve25519.X25519(ephemeralB, publicKeyA)
```

## Encryption

p.s. 截取代码删去了一些错误处理和检查

Wrap 函数的参数 fileKey 是实际上用来加密文本的密钥，Wrap 首先通过前文提到的 ECDHE 算法计算出 sharedSecret。之后对 sharedSecret 进行加盐 hkdf 操作，生成用于 aead 加密的 wrappingKey，使用 wrappingKey 对 fileKey 进行加密。注意这里的 aead 并没有是用随机生成的 nonce,而是使用了全部字节为 0 的固定 nonce, 原因是在这里加密的密钥是是一次性的，没有必要再使用随机 nonce。

```golang
type Stanza struct {
  Type string
  Args []string
  Body []byte
}

func (r *X25519Recipient) Wrap(fileKey []byte) ([]*Stanza, error) {
    ephemeral := make([]byte, curve25519.ScalarSize)
    rand.Read(ephemeral)
    ourPublicKey, err := curve25519.X25519(ephemeral, curve25519.Basepoint)

    sharedSecret, err := curve25519.X25519(ephemeral, r.theirPublicKey)

    l := &Stanza{
        Type: "X25519",
        Args: []string{format.EncodeToString(ourPublicKey)},
    }

    salt := make([]byte, 0, len(ourPublicKey)+len(r.theirPublicKey))
    salt = append(salt, ourPublicKey...)
    salt = append(salt, r.theirPublicKey...)
    h := hkdf.New(sha256.New, sharedSecret, salt, []byte(x25519Label))
    wrappingKey := make([]byte, chacha20poly1305.KeySize)
    io.ReadFull(h, wrappingKey)

    wrappedKey, err := aeadEncrypt(wrappingKey, fileKey)

    l.Body = wrappedKey

  return []*Stanza{l}, nil
}
```

age 定义了一种新的密文格式，第一行是格式的版本，随后是 header 其中包含了多条 stanza 记录，可以简单理解成接收人记录，最后是加密过后的密文。age 的密文可以有多个接收人，因此 Encrypt 中需要使用每个接收人的公钥进行一次计算。首先生成随机的 fileKey, 然后通过 wrap 函数使用每一个接收人的公钥对 fileKey 进行加密，构造一条 stanza 记录加入 header 中，随后更新 header mac。stanza 的第一个字段为算法类型，在这里为 X25519，第二个字段用来存放发送方的公钥，第三个字段为 wrappedKey 即 warp 加密后的 fileKey。最后 Encrypt 将 header 写入 dst，随后是随机生成 aead nonce, 返回一个使用 streamKey 和 dst 构造的加密 stream writer, 后续将要加密的文本写入这个加密 stream writer 即可完成整个加密流程。

```golang

func Encrypt(dst io.Writer, recipients ...Recipient) (io.WriteCloser, error) {
    fileKey := make([]byte, fileKeySize)
    rand.Read(fileKey）

    hdr := &format.Header{}
    for i, r := range recipients {
        stanzas, err := r.Wrap(fileKey)
        for _, s := range stanzas {
            hdr.Recipients = append(hdr.Recipients, (*format.Stanza)(s))
        }
    }

    mac, err := headerMAC(fileKey, hdr)
    hdr.MAC = mac

    hdr.Marshal(dst)

    nonce := make([]byte, streamNonceSize)
    rand.Read(nonce)
    dst.Write(nonce)

    return stream.NewWriter(streamKey(fileKey, nonce), dst)
}
```

## Decryption

解密过程的第一步是通过 unwrap 得到 fileKey。首先完成 ECDH 得到 sharedSecret，之后使用与 wrap 相同的加盐 hkdf 得到 wrappingKey， 使用 wrappingKey 即可从 stanza 的 body 字段中解密出 fileKey。

```golang
func (i *X25519Identity) unwrap(block *Stanza) ([]byte, error) {
    publicKey, err := format.DecodeString(block.Args[0])

    sharedSecret, err := curve25519.X25519(i.secretKey, publicKey)

    salt := make([]byte, 0, len(publicKey)+len(i.ourPublicKey))
    salt = append(salt, publicKey...)
    salt = append(salt, i.ourPublicKey...)
    h := hkdf.New(sha256.New, sharedSecret, salt, []byte(x25519Label))
    wrappingKey := make([]byte, chacha20poly1305.KeySize)
    io.ReadFull(h, wrappingKey)

    fileKey, err := aeadDecrypt(wrappingKey, fileKeySize, block.Body)

    return fileKey, nil
}
```

Decrypt 从 header 的多条 stanza 记录中匹配能够 unwarp 的 stanza, 获得 fileKey, 之后校验 header mac, 取出 nonce, 最后构造了一个解密 stream reader, 从 stream reader 中即可读取解密的文本。

```golang
func Decrypt(src io.Reader, identities ...Identity) (io.Reader, error) {
    hdr, payload, err := format.Parse(src)

    stanzas := make([]*Stanza, 0, len(hdr.Recipients))
    for _, s := range hdr.Recipients {
        stanzas = append(stanzas, (*Stanza)(s))
    }

    errNoMatch := &NoIdentityMatchError{}
    var fileKey []byte
    for _, id := range identities {
        fileKey, err = id.Unwrap(stanzas)
        if errors.Is(err, ErrIncorrectIdentity) {
            errNoMatch.Errors = append(errNoMatch.Errors, err)
            continue
        }
        if err != nil {
            return nil, err
        }

        break
  }

    if mac, err := headerMAC(fileKey, hdr); err != nil {
        return nil, fmt.Errorf("failed to compute header MAC: %v", err)
    } else if !hmac.Equal(mac, hdr.MAC) {
        return nil, errors.New("bad header MAC")
    }

    nonce := make([]byte, streamNonceSize)
    io.ReadFull(payload, nonce)

    return stream.NewReader(streamKey(fileKey, nonce), payload)
}
```
