# Разделяемая между fork-процессами память и мьютекс на ней.
#
# Модель nginx: страница анонимного mmap(MAP_SHARED|MAP_ANON) создаётся в
# master ДО fork — дети наследуют маппинг автоматически (одна физическая
# память во всех процессах, ядро гарантирует когерентность). Файловой
# системы нет вообще: ни блокировки inode (flock/fcntl), ни каталога —
# лок не зависит от того, где лежит база (tmpfs, ext4, докер-тома).
#
# Мьютекс — pthread с PTHREAD_PROCESS_SHARED (живёт в разделяемой
# странице) и PTHREAD_MUTEX_ROBUST: смерть держателя не клиничит
# остальных — следующий lock вернёт EOWNERDEAD, лок восстанавливается
# pthread_mutex_consistent. Это то же свойство авто-освобождения при
# смерти процесса, что у flock. Константы — стабильные значения Linux
# ABI (glibc и musl), поэтому биндинги самодостаточны.
#
# Блокирующий lock спит в C и замораживает event-loop процесса — как и
# flock раньше; безопасно, пока держатель живёт в ДРУГОМ процессе (у
# каждого свой цикл) и времена удержания микросекундные.

lib LibPShm
  PROT_READ  = 1
  PROT_WRITE = 2
  MAP_SHARED = 0x01
  MAP_ANON   = 0x20

  # Linux errno (asm-generic: одинаковые на glibc/musl, x86_64/aarch64).
  EOWNERDEAD = 130

  # pthread attr-значения POSIX.
  PTHREAD_PROCESS_SHARED = 1
  PTHREAD_MUTEX_ROBUST   = 1

  fun mmap(addr : Void*, len : UInt64, prot : Int32, flags : Int32,
           fd : Int32, off : Int64) : Void*
  fun munmap(addr : Void*, len : UInt64) : Int32

  # Остальные pthread_mutex_* уже объявлены в LibC stdlib (с типами
  # PthreadMutexT/PthreadMutexattrT) — ре-декларация с другой сигнатурой
  # запрещена; этих трёх в stdlib нет.
  fun pthread_mutexattr_setpshared(attr : LibC::PthreadMutexattrT*, pshared : Int32) : Int32
  fun pthread_mutexattr_setrobust(attr : LibC::PthreadMutexattrT*, robust : Int32) : Int32
  fun pthread_mutex_consistent(mutex : LibC::PthreadMutexT*) : Int32
end

module ActiveSupport
  # Страница анонимной разделяемой памяти, унаследованная форками.
  # Выделяется в master до fork; дети получают тот же указатель
  # (адресное пространство наследуется целиком).
  class SharedPage
    DEFAULT_SIZE = 4096

    getter size : Int32
    @ptr : Pointer(UInt8)

    def initialize(@size : Int32 = DEFAULT_SIZE)
      @ptr = LibPShm.mmap(Pointer(Void).null, @size.to_u64!,
        LibPShm::PROT_READ | LibPShm::PROT_WRITE,
        LibPShm::MAP_SHARED | LibPShm::MAP_ANON, -1, 0).as(Pointer(UInt8))
      raise IO::Error.new("mmap shared page failed") if @ptr.address == 0
    end

    def pointer(offset : Int32 = 0) : Pointer(UInt8)
      @ptr + offset
    end

    # Страница живёт до конца процесса: munmap не делаем — дети
    # наследуют маппинг, форк-перезапуски master'а его переиспользуют.
    def to_slice : Bytes
      Slice.new(@ptr, @size)
    end
  end

  # Robust process-shared мьютекс по адресу в SharedPage (хранение —
  # сама страница, смещение передаётся указателем).
  class ProcessSharedMutex
    # Инициализация мьютекса по нулевому смещению страницы. Вызывать
    # один раз до fork; повторный вызов на той же странице — ошибка.
    def self.init_at(ptr : Pointer(UInt8)) : self
      mutex = new(ptr)
      # attr живёт только внутри инициализации — на стеке, без malloc/free.
      attr = uninitialized LibC::PthreadMutexattrT
      rc = LibC.pthread_mutexattr_init(pointerof(attr))
      raise "pthread_mutexattr_init failed rc=#{rc}" unless rc == 0
      begin
        rc = LibPShm.pthread_mutexattr_setpshared(pointerof(attr), LibPShm::PTHREAD_PROCESS_SHARED)
        raise "setpshared failed rc=#{rc}" unless rc == 0
        rc = LibPShm.pthread_mutexattr_setrobust(pointerof(attr), LibPShm::PTHREAD_MUTEX_ROBUST)
        raise "setrobust failed rc=#{rc}" unless rc == 0
        rc = LibC.pthread_mutex_init(ptr.as(LibC::PthreadMutexT*), pointerof(attr))
        raise "pthread_mutex_init failed rc=#{rc}" unless rc == 0
      ensure
        LibC.pthread_mutexattr_destroy(pointerof(attr))
      end
      mutex
    end

    def initialize(@ptr : Pointer(UInt8))
    end

    # Блокирующий захват. EOWNERDEAD — прошлый держатель умер, не
    # отпустив: лок наш, состояние критической секции на совести
    # вызывающего (SQLite-транзакция атомарна — продолжаем).
    def lock : Nil
      rc = LibC.pthread_mutex_lock(@ptr.as(LibC::PthreadMutexT*))
      if rc == LibPShm::EOWNERDEAD
        rc2 = LibPShm.pthread_mutex_consistent(@ptr.as(LibC::PthreadMutexT*))
        raise "pthread_mutex_consistent failed rc=#{rc2}" unless rc2 == 0
      elsif rc != 0
        raise "pthread_mutex_lock failed rc=#{rc}"
      end
    end

    def unlock : Nil
      rc = LibC.pthread_mutex_unlock(@ptr.as(LibC::PthreadMutexT*))
      raise "pthread_mutex_unlock failed rc=#{rc}" unless rc == 0
    end
  end
end
