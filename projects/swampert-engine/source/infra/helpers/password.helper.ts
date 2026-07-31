export class PasswordHelper {
  static hash(password: string) {
    return Bun.password.hash(password);
  }

  static verify(password: string, hash: string) {
    return Bun.password.verify(password, hash);
  }
}
