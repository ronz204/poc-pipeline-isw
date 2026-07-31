export const hashSeed = (base: number, value: string) =>
  [...value].reduce((hash, char) => (hash * 31 + char.charCodeAt(0)) >>> 0, base);

export class SeededRandom {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  };

  private next(): number {
    this.state = (this.state * 1103515245 + 12345) & 0x7fffffff;
    return this.state / 0x7fffffff;
  };

  public pick<T>(items: readonly T[]): T {
    return items[Math.floor(this.next() * items.length)]!;
  };

  public pickSubset<T>(items: readonly T[], count: number): T[] {
    const pool = [...items];
    const picked: T[] = [];
    const target = Math.min(count, pool.length);

    for (let i = 0; i < target; i++) {
      const index = Math.floor(this.next() * pool.length);
      picked.push(pool.splice(index, 1)[0]!);
    };

    return picked;
  };
};
