int sum_to(int n) {
    int s = 0;
    for (int i = 1; i <= n; ++i) s += i;
    return s;
}

int main(void) {
    volatile int result = sum_to(10);
    return result == 55 ? 0 : 1;
}
