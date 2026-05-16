import asyncio
import sys
import edge_tts


async def main():
    text = sys.argv[1] if len(sys.argv) > 1 else "Hello world, calling worked"
    out = sys.argv[2] if len(sys.argv) > 2 else "hello.wav"

    communicate = edge_tts.Communicate(text, "en-US-JennyNeural")
    await communicate.save(out)
    print(f"Saved {out}")


if __name__ == "__main__":
    asyncio.run(main())
