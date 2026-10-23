<template>
  <span class="typing-dots"><span/><span/><span/></span>
</template>

<style scoped>
.typing-dots {
  display: inline-flex;
  gap: 4px;
}

.typing-dots span {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
  animation: typing 1.2s infinite ease-in-out;
}

.typing-dots span:nth-child(2) {
  animation-delay: 0.15s;
}

.typing-dots span:nth-child(3) {
  animation-delay: 0.3s;
}

@keyframes typing {
  0%, 80%, 100% {
    opacity: 0.25;
    transform: translateY(0);
  }
  40% {
    opacity: 1;
    transform: translateY(-3px);
  }
}
</style>
