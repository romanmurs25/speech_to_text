export class RequestDeduplicator<T> {
  private readonly completed = new Map<string, T>();
  private readonly inFlight = new Map<string, Promise<T>>();

  async run(key: string, operation: () => Promise<T>): Promise<T> {
    const completed = this.completed.get(key);
    if (completed) {
      return completed;
    }

    const existing = this.inFlight.get(key);
    if (existing) {
      return existing;
    }

    const pending = operation()
      .then((value) => {
        this.completed.set(key, value);
        return value;
      })
      .finally(() => {
        this.inFlight.delete(key);
      });

    this.inFlight.set(key, pending);
    return pending;
  }
}
