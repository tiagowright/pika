# Code signing Pika builds

macOS keys the Accessibility permission to an app's **code signature**. An
ad-hoc signature is different on every build, so an ad-hoc Pika loses its
permission every time you rebuild and then silently stops raising windows.

`build.sh` chooses a signing identity, first match wins:

1. `$PIKA_SIGN_IDENTITY`
2. `.signing-identity` — a one-line file in the project root, gitignored
3. A `Developer ID Application` certificate in your keychain
4. Ad-hoc, with a warning explaining the above

For comfortable local development, create a stable identity once:

**Keychain Access → Certificate Assistant → Create a Certificate…** → choose
any name, **Identity Type: Self Signed Root**, and **Certificate Type: Code
Signing**. Then create `.signing-identity` containing that certificate name:

```sh
echo "My Local Signing" > .signing-identity
```

The first build with a new key raises a keychain prompt. Choose **Always
Allow**. Choosing only **Allow** makes each subsequent build stop at the same
dialog.
