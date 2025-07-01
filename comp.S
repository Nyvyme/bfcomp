        .text
        .globl  _start
_start:
        movl    (%rsp), %eax
        movl    %eax, .L_DATA_argc(%rip)

        leaq    8(%rsp), %rax
        movq    %rax, .L_DATA_argv(%rip)

        # Allocate space on stack
        subq    $72, %rsp

        # Stack layout:
        #   (%rsp) -- filename
        #  8(%rsp) -- memory size
        # 16(%rsp) -- file size
        # 24(%rsp) -- file in
        # 32(%rsp) -- file out
        # 48(%rsp) -- data
        # 56(%rsp) -- data size
        # 64(%rsp) -- error code storage

        # Set stack variables to zero
        movq    $0, (%rsp)
        movq    $0, 16(%rsp)
        movq    $0, 24(%rsp)
        movq    $0, 32(%rsp)
        movq    $0, 56(%rsp)
        movq    $0, 64(%rsp)

        # Set memory size to default (128)
        leaq    .L_RODATA_default_memory_size(%rip), %rax
        movq    %rax, 8(%rsp)

        # If argc < 2
        cmpl    $2, .L_DATA_argc(%rip)
        jl      .Lno_input

        # Put filename (argv[1]) to the stack (%rsp)
        movq    .L_DATA_argv(%rip), %rax
        movq    8(%rax), %rbx
        movq    %rbx, (%rsp)

        # If argc >= 3
        cmpl    $3, .L_DATA_argc(%rip)
        jl      .Ldont_set_memory_size

        # Put memory size (argv[2]) to the stack 8(%rsp)
        movq    16(%rax), %rbx
        movq    %rbx, 8(%rsp)

.Ldont_set_memory_size:

        # Open input file
        movq    $2, %rax
        movq    (%rsp), %rdi
        xorq    %rsi, %rsi
        movq    $0666, %rdx
        syscall

        # Check if input file descriptor is invalid
        cmpq    $-2, %rax
        je      .Lfailed_to_open_input

        # Move input file descriptor to stack 24(%rsp)
        movq    %rax, 24(%rsp)

        # Open output file
        movq    $2, %rax
        leaq    .L_RODATA_output(%rip), %rdi
        movq    $0x41, %rsi
        movq    $0666, %rdx
        syscall

        # Check if output file descriptor is invalid
        cmpq    $-2, %rax
        je      .Lfailed_to_open_output

        # Move output file descriptor to stack 32(%rsp)
        movq    %rax, 32(%rsp)

        # Get file size via stat syscall
        movq    $4, %rax
        movq    (%rsp), %rdi
        leaq    .L_DATA_file_stat(%rip), %rsi
        syscall

        # Save file size to the stack 56(%rsp)
        leaq    .L_DATA_file_stat(%rip), %rdi
        movq    48(%rdi), %rsi # File size is offsetted by 48 bytes
        movq    %rsi, 56(%rsp)

        # Allocate memory via mmap syscall
        movq    $9, %rax
        leaq    .L_DATA_file_stat(%rip), %rdi
        movq    48(%rdi), %rsi # File size is offsetted by 48 bytes
        xorq    %rdi, %rdi
        movq    $3, %rdx  # PROT_READ | PROT_WRITE
        movq    $33, %r10 # MAP_ANONYMOUS | MAP_SHARED
        xorq    %r9, %r9
        xorq    %r8, %r8
        syscall

        # Move pointer to memory to the stack 48(%rsp)
        movq    %rax, 48(%rsp)

        # Read data from the file via read syscall
        xorq    %rax, %rax
        leaq    .L_DATA_file_stat(%rip), %rdi
        movq    48(%rdi), %rdx
        movq    24(%rsp), %rdi
        movq    48(%rsp), %rsi
        syscall

        # Print data
        movq    48(%rsp), %rdi
        callq   println

        # Go to the main compilation routine
        movq    48(%rsp), %rdi
        movq    56(%rsp), %rsi
        movq    8(%rsp), %rdx
        movq    32(%rsp), %rcx
        callq   compile

        leaq    .L_MSG_success(%rip), %rdi
        callq   println

        xorq    %rdi, %rdi
.Lend:
        movq    %rdi, 64(%rsp)

        # Check if input file descriptor is empty
        cmpq    $0, 24(%rsp)
        je      .Lend_next_0

        # Close file handle
        movq    $3, %rax
        movq    24(%rsp), %rdi
        syscall

.Lend_next_0:
        # Check if output file descriptor is empty
        cmpq    $0, 32(%rsp)
        je      .Lend_next_1

        # Close file handle
        movq    $3, %rax
        movq    32(%rsp), %rdi
        syscall

.Lend_next_1:
        # Check if pointer to allocated data is nullptr
        cmpq    $0, 48(%rsp)
        je      .Lend_next_2

        # Free allocated data
        movq    $11, %rax
        movq    48(%rsp), %rdi
        movq    56(%rsp), %rsi
        syscall

.Lend_next_2:
        movq    64(%rsp), %rdi
        addq    $72, %rsp
        movq    $60, %rax
        syscall

.Lno_input:
        leaq    .L_MSG_no_input_file(%rip), %rdi
        callq   println

        movq    $-1, %rdi
        jmp     .Lend

.Lfailed_to_open_input:
        leaq    .L_MSG_failed_to_open_input(%rip), %rdi
        callq   println

        movq    $-2, %rdi
        jmp     .Lend

.Lfailed_to_open_output:
        leaq    .L_MSG_failed_to_open_output(%rip), %rdi
        callq   println

        movq    $-3, %rdi
        jmp     .Lend

.Lclose_loop_error:
        leaq    .L_MSG_close_loop_error(%rip), %rdi
        callq   println

        movq    $-4, %rdi
        jmp     .Lend

# %rdi - data
# %rsi - data size
# %rdx - memory size
# %rcx - output file
compile:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $32, %rsp

        # Stack layout:
        #   (%rsp) -- data
        #  8(%rsp) -- data size
        # 16(%rsp) -- memory size
        # 24(%rsp) -- output file
        movq    %rdi, (%rsp)
        movq    %rsi, 8(%rsp)
        movq    %rdx, 16(%rsp)
        movq    %rcx, 24(%rsp)

        # Place header
        movq    %rcx, %rdi
        movq    %rdx, %rsi
        callq   place_header

        # Compile program
        movq    (%rsp), %rdi
        movq    8(%rsp), %rsi
        movq    24(%rsp), %rdx
        callq   _compile

        # Place end
        movq    24(%rsp), %rdi
        movq    16(%rsp), %rsi
        callq   place_end

        addq    $32, %rsp
        popq    %rbp
        retq

# %rdi - file descriptor
# %rsi - memory size
place_header:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $24, %rsp

        # Stack layout:
        #   (%rsp) -- memory size
        #  8(%rsp) -- file descriptor storage
        # 16(%rsp) -- length of memory size string
        movq    %rsi, (%rsp)
        movq    %rdi, 8(%rsp)

        movq    %rsi, %rdi
        callq   strlen
        movq    %rax, 16(%rsp)

        # Place first part of the header
        movq    $1, %rax
        movq    8(%rsp), %rdi
        leaq    .L_RODATA_header1(%rip), %rsi
        movq    $67, %rdx
        syscall

        # Place memory length that will be subtracted from RSP
        movq    $1, %rax
        movq    8(%rsp), %rdi
        movq    (%rsp), %rsi
        movq    16(%rsp), %rdx
        syscall

        # Place second part of the header
        movq    $1, %rax
        movq    8(%rsp), %rdi
        leaq    .L_RODATA_header2(%rip), %rsi
        movq    $44, %rdx
        syscall

        # Place memory length that will be compared to R8
        movq    $1, %rax
        movq    8(%rsp), %rdi
        movq    (%rsp), %rsi
        movq    16(%rsp), %rdx
        syscall

        # Place third part of the header
        movq    $1, %rax
        movq    8(%rsp), %rdi
        leaq    .L_RODATA_header3(%rip), %rsi
        movq    $91, %rdx
        syscall

        addq    $24, %rsp
        popq    %rbp
        retq

# %rdi - file descriptor
# %rsi - memory size
place_end:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $24, %rsp

        # Stack layout:
        #   (%rsp) -- memory size
        #  8(%rsp) -- file descriptor storage
        # 16(%rsp) -- length of memory size string
        movq    %rsi, (%rsp)
        movq    %rdi, 8(%rsp)

        movq    %rsi, %rdi
        callq   strlen
        movq    %rax, 16(%rsp)

        # Place first part of end
        movq    $1, %rax
        movq    8(%rsp), %rdi
        leaq    .L_RODATA_end1(%rip), %rsi
        movq    $8, %rdx
        syscall

        # Place memory size that will be added to RSP
        movq    $1, %rax
        movq    8(%rsp), %rdi
        movq    (%rsp), %rsi
        movq    16(%rsp), %rdx
        syscall

        # Place second part of end
        movq    $1, %rax
        movq    8(%rsp), %rdi
        leaq    .L_RODATA_end2(%rip), %rsi
        movq    $50, %rdx
        syscall

        addq    $24, %rsp
        popq    %rbp
        retq

# %rdi - data
# %rsi - data size
# %rdx - file descriptor
_compile:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $8264, %rsp

        # Stack layout:
        #   (%rsp) -- Pointer to data                           (8)
        #  8(%rsp) -- Data size                                 (8)
        # 16(%rsp) -- Loop stack index                          (8)
        # 24(%rsp) -- Loop counter                              (8)
        # 32(%rsp) -- Loop index                                (8)
        # 48(%rsp) -- Buffered character times                  (8)
        # 56(%rsp) -- File descriptor                           (4)
        # 60(%rsp) -- Character                                 (1)
        # 61(%rsp) -- Buffered character                        (1)
        # 64(%rsp) -- Forloop index                             (8)
        # 72(%rsp) -- Loop stack (1024 * sizeof(size_t))        (8192)
        movq    %rdi, (%rsp)
        movq    %rsi, 8(%rsp)
        movl    %edx, 56(%rsp)

        # Clear values that should be cleared
        movq    $0, 16(%rsp)
        movq    $0, 24(%rsp)
        movq    $0, 32(%rsp)
        movq    $0, 48(%rsp)
        movb    $0, 61(%rsp)
        movq    $0, 64(%rsp)

.Lcompile_loop:
        # If "Forloop index" is equal to "Data size", exit
        movq    64(%rsp), %rcx
        cmpq    8(%rsp), %rcx
        je      .Lcompile_end

        # Store character from data buffer in stack 60(%rsp)
        movq    (%rsp), %rax
        movb    (%rax, %rcx), %bl
        movb    %bl, 60(%rsp)

        jmp     .Lcompile_to_rep_instruction
.Lcompile_loop_continue:

.Lcompile_loop_c_is_right_arrow:
        # If character is '>'
        cmpb    $'>', 60(%rsp)
        jne     .Lcompile_loop_c_is_left_arrow

        movb    60(%rsp), %al
        movb    %al, 61(%rsp)
        incq    48(%rsp)

        jmp     .Lcompile_loop_advance

.Lcompile_loop_c_is_left_arrow:
        cmpb    $'<', 60(%rsp)
        jne     .Lcompile_loop_c_is_plus

        movb    60(%rsp), %al
        movb    %al, 61(%rsp)
        incq    48(%rsp)

        jmp     .Lcompile_loop_advance

.Lcompile_loop_c_is_plus:
        cmpb    $'+', 60(%rsp)
        jne     .Lcompile_loop_c_is_minus

        movb    60(%rsp), %al
        movb    %al, 61(%rsp)
        incq    48(%rsp)

        jmp     .Lcompile_loop_advance

.Lcompile_loop_c_is_minus:
        cmpb    $'-', 60(%rsp)
        jne     .Lcompile_loop_c_is_period

        movb    60(%rsp), %al
        movb    %al, 61(%rsp)
        incq    48(%rsp)

        jmp     .Lcompile_loop_advance

.Lcompile_loop_c_is_period:
        cmpb    $'.', 60(%rsp)
        jne     .Lcompile_loop_c_is_comma

        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_output_op(%rip), %rsi
        movq    $78, %rdx
        syscall

        jmp     .Lcompile_loop_advance

.Lcompile_loop_c_is_comma:
        cmpb    $',', 60(%rsp)
        jne     .Lcompile_loop_c_is_open_bracket

        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_input_op(%rip), %rsi
        movq    $82, %rdx
        syscall

        jmp     .Lcompile_loop_advance

.Lcompile_loop_c_is_open_bracket:
        cmpb    $'[', 60(%rsp)
        jne     .Lcompile_loop_c_is_close_bracket

        # Put value from loop counter to the loop stack
        movq    16(%rsp), %rcx
        leaq    72(%rsp), %rax
        movq    24(%rsp), %rbx
        movq    %rbx, (%rax, %rcx, 8)
        # Increment loop stack index
        incq    16(%rsp)

        # Put label prefix
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_label_prefix(%rip), %rsi
        movq    $2, %rdx
        syscall

        # Format hex value to string
        movq    24(%rsp), %rdi
        callq   xtoa_zeros

        # Put formatted string
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_DATA_numbuf(%rip), %rsi
        movq    $16, %rdx
        syscall

        # Put label suffix
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_label_suffix(%rip), %rsi
        movq    $2, %rdx
        syscall

        # Put first part of the operation
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_open_brack1(%rip), %rsi
        movq    $28, %rdx
        syscall

        # Put formatted string
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_DATA_numbuf(%rip), %rsi
        movq    $16, %rdx
        syscall

        # Put second part of the operation
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_open_brack2(%rip), %rsi
        movq    $5, %rdx
        syscall

        # Increment loop counter
        incq    24(%rsp)

        jmp     .Lcompile_loop_advance

.Lcompile_loop_c_is_close_bracket:
        cmpb    $']', 60(%rsp)
        jne     .Lcompile_loop_advance

        # Check if loop stack index is zero
        cmpq    $0, 16(%rsp)
        je      .Lclose_loop_error

        # Put value from loop stack to loop index
        decq    16(%rsp)
        movq    16(%rsp), %rcx
        leaq    72(%rsp), %rax
        movq    (%rax, %rcx, 8), %rbx
        movq    %rbx, 32(%rsp)

        # Put first part of close bracket operation
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_close_brack1(%rip), %rsi
        movq    $7, %rdx
        syscall

        # Format hex value to string
        movq    32(%rsp), %rdi
        callq   xtoa_zeros

        # Put formatted string
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_DATA_numbuf(%rip), %rsi
        movq    $16, %rdx
        syscall

        # Put second part of close bracket operation
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_close_brack2(%rip), %rsi
        movq    $1, %rdx
        syscall

        # Put end label prefix
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_label_prefix(%rip), %rsi
        movq    $2, %rdx
        syscall

        # Put formatted string
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_DATA_numbuf(%rip), %rsi
        movq    $16, %rdx
        syscall

        # Put third part of close bracket operation
        movq    $1, %rax
        movl    56(%rsp), %edi
        leaq    .L_RODATA_close_brack3(%rip), %rsi
        movq    $6, %rdx
        syscall

.Lcompile_loop_advance:
        incq    64(%rsp)
        jmp     .Lcompile_loop

.Lcompile_end:
        addq    $8264, %rsp
        popq    %rbp
        retq

.Lcompile_to_rep_instruction:
        # Check if buffered character is empty
        cmpb    $0, 61(%rsp)
        je      .Lcompile_loop_continue

        # Check if buffered character is not current character
        movb    60(%rsp), %bl
        cmpb    61(%rsp), %bl
        je      .Lcompile_loop_continue

        # Check if buffered character times is zero
        movq    48(%rsp), %rax
        cmpq    $0, %rax
        je      .Lcompile_loop_continue

        movb    61(%rsp), %dil
        movq    48(%rsp), %rsi
        movl    56(%rsp), %edx
        callq   put_repeating_instruction

        # Clear buffered character and buffered character times
        movq    $0, 48(%rsp)
        movb    $0, 61(%rsp)
        jmp     .Lcompile_loop_continue

# %dil - character
# %rsi - repeat times
# %edx - file descriptor
put_repeating_instruction:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $16, %rsp

        # Stack layout:
        #   (%rsp) -- Repeat times
        #  8(%rsp) -- File descriptor
        # 12(%rsp) -- Character
        movq    %rsi, (%rsp)
        movl    %edx, 8(%rsp)
        movb    %dil, 12(%rsp)

        cmpq    $1, %rsi
        ja      .Lput_rep_ins_more_than_1

        # Repeat times is 1

.Lput_rep_ins_rarrow:
        cmpb    $'>', 12(%rsp)
        jne     .Lput_rep_ins_larrow

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_rarrow_once(%rip), %rsi
        movq    $10, %rdx
        syscall

        jmp     .Lput_rep_ins_end

.Lput_rep_ins_larrow:
        cmpb    $'<', 12(%rsp)
        jne     .Lput_rep_ins_plus

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_larrow_once(%rip), %rsi
        movq    $10, %rdx
        syscall

        jmp     .Lput_rep_ins_end

.Lput_rep_ins_plus:
        cmpb    $'+', 12(%rsp)
        jne     .Lput_rep_ins_minus

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_plus_once(%rip), %rsi
        movq    $18, %rdx
        syscall

        jmp     .Lput_rep_ins_end

.Lput_rep_ins_minus:
        cmpb    $'-', 12(%rsp)
        jne     .Lput_rep_ins_end

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_minus_once(%rip), %rsi
        movq    $18, %rdx
        syscall

        jmp     .Lput_rep_ins_end

.Lput_rep_ins_more_than_1:
        cmpb    $'>', 12(%rsp)
        jne     .Lput_rep_ins_larrow_mul

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_rarrow_mul1(%rip), %rsi
        movq    $7, %rdx
        syscall

        movq    (%rsp), %rdi
        callq   itoa_number
        movq    %rax, %rdx
        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_DATA_numbuf(%rip), %rsi
        syscall

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_rarrow_mul2(%rip), %rsi
        movq    $6, %rdx
        syscall

        jmp     .Lput_rep_ins_end

.Lput_rep_ins_larrow_mul:
        cmpb    $'<', 12(%rsp)
        jne     .Lput_rep_ins_plus_mul

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_larrow_mul1(%rip), %rsi
        movq    $7, %rdx
        syscall

        movq    (%rsp), %rdi
        callq   itoa_number
        movq    %rax, %rdx
        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_DATA_numbuf(%rip), %rsi
        syscall

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_larrow_mul2(%rip), %rsi
        movq    $6, %rdx
        syscall

        jmp     .Lput_rep_ins_end

.Lput_rep_ins_plus_mul:
        cmpb    $'+', 12(%rsp)
        jne     .Lput_rep_ins_minus_mul

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_plus_mul1(%rip), %rsi
        movq    $7, %rdx
        syscall

        movq    (%rsp), %rdi
        callq   itoa_number
        movq    %rax, %rdx
        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_DATA_numbuf(%rip), %rsi
        syscall

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_plus_mul2(%rip), %rsi
        movq    $14, %rdx
        syscall

        jmp     .Lput_rep_ins_end

.Lput_rep_ins_minus_mul:
        cmpb    $'-', 12(%rsp)
        jne     .Lput_rep_ins_end

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_minus_mul1(%rip), %rsi
        movq    $7, %rdx
        syscall

        movq    (%rsp), %rdi
        callq   itoa_number
        movq    %rax, %rdx
        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_DATA_numbuf(%rip), %rsi
        syscall

        movq    $1, %rax
        movl    8(%rsp), %edi
        leaq    .L_RODATA_minus_mul2(%rip), %rsi
        movq    $14, %rdx
        syscall

.Lput_rep_ins_end:
        addq    $16, %rsp
        popq    %rbp
        retq

# %rdi - string
print:
        # Move string to RSI for sys_write (1)
        movq    %rdi, %rsi

        # Get string length
        callq   strlen
        movq    %rax, %rdx

        # Print string
        movq    $1, %rax
        movq    $1, %rdi
        syscall

        retq

# %rdi - String
println:
        # Print string
        callq   print

        # Print linefeed character
        movq    $1, %rax
        movq    $1, %rdi
        leaq    .L_RODATA_linefeed(%rip), %rsi
        movq    $1, %rdx
        syscall

        retq

# %rdi - string
# %rax - out
strlen:
        movq    %rdi, %rsi

        xorb    %al, %al

.strlen_loop:
        scasb
        je      .strlen_end
        jmp     .strlen_loop

.strlen_end:
        movq    %rdi, %rax
        subq    %rsi, %rax

        decq    %rax

        retq

# Input:
#   %rdi - value
# Output:
#   %rax - string length
# formatted string will be in .L_DATA_numbuf
# NOTE: Only works with possitive values.
itoa_number:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $24, %rsp

        # Stack layout:
        #  (%rsp) -- Value
        # 8(%rsp) -- Stored length
        movq    %rdi, (%rsp)
        movq    $0, 8(%rsp)

        # Clear .L_DATA_numbuf
        leaq    .L_DATA_numbuf(%rip), %rax
        movq    $0, (%rax)
        movq    $0, 8(%rax)

        # Get length
        movq    (%rsp), %rax
        movl    $10, %ecx
.Litoa_number_length_loop:
        xorq    %rdx, %rdx
        cmpq    $0, %rax
        je      .Litoa_number_length_end
        incq    8(%rsp)
        divl    %ecx
        jmp     .Litoa_number_length_loop
.Litoa_number_length_end:

        # Put numbers into the string
        movq    (%rsp), %rax
        movl    $10, %ecx
        movq    8(%rsp), %rdi
        leaq    .L_DATA_numbuf(%rip), %rbx
.Litoa_number_put_loop:
        xorq    %rdx, %rdx
        cmpq    $0, %rdi
        je      .Litoa_number_put_end

        # Get 1-digit value
        divl    %ecx
        addl    $'0', %edx

        movb    %dl, -1(%rbx, %rdi)

        decq    %rdi
        jmp     .Litoa_number_put_loop
.Litoa_number_put_end:

        movq    8(%rsp), %rax

        addq    $24, %rsp
        popq    %rbp
        retq

# Input:
#   %rdi - value
# formatted string will be in .L_DATA_numbuf
# NOTE: Only works with possitive values.
xtoa_zeros:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $8, %rsp

        # Stack layout:
        # (%rsp) -- Value
        movq    %rdi, (%rsp)

        # Set every byte of .L_DATA_numbuf to '0'
        movq    $0, %rcx
        leaq    .L_DATA_numbuf(%rip), %rax
.Lxtoa_zeros_put_zeros_loop:
        cmpq    $16, %rcx
        je      .Lxtoa_zeros_put_zeros_end

        movb    $'0', (%rax, %rcx)

        incq    %rcx
        jmp     .Lxtoa_zeros_put_zeros_loop
.Lxtoa_zeros_put_zeros_end:

        # Set character numbers
        movq    $16, %rcx
        movq    (%rsp), %rbx
.Lxtoa_zeros_format_loop:
        # Check if iterator is zero
        cmpq    $0, %rcx
        je      .Lxtoa_zeros_format_end
        # Check if value is zero
        cmpq    $0, %rbx
        je      .Lxtoa_zeros_format_end

        # Check if first digit is greater than or equal to 0xA
        movq    %rbx, %rdx
        andq    $0xF, %rdx
        cmpb    $0xA, %dl
        jge     .Lxtoa_zeros_format_loop_use_alpha

        # Format digit as ASCII digit
        addb    $'0', %dl

        jmp     .Lxtoa_zeros_format_loop_continue

.Lxtoa_zeros_format_loop_use_alpha:
        # Format digit as ASCII letter
        addb    $'A', %dl
        subb    $0xA, %dl

.Lxtoa_zeros_format_loop_continue:
        leaq    .L_DATA_numbuf(%rip), %rax
        movb    %dl, -1(%rax, %rcx)

        decq    %rcx
        shrq    $4, %rbx
        jmp     .Lxtoa_zeros_format_loop
.Lxtoa_zeros_format_end:

        addq    $8, %rsp
        popq    %rbp
        retq

        .data
### Read-only data ###
.L_RODATA_output:
        .asciz  "out.S"

.L_RODATA_linefeed:
        .ascii  "\n"

.L_RODATA_default_memory_size:
        .asciz  "128"

# Header
.L_RODATA_header1: # 67 bytes
        .ascii  "# Assembly file generated by BfComp\n"
        .ascii  "\n"
        .ascii  "\t.globl _start\n"
        .ascii  "_start:\n"
        .ascii  "\tsubq $"
.L_RODATA_header2: # 44 bytes
        .ascii  ", %rsp\n"
        .ascii  "\n"
        .ascii  "\txorq %r8, %r8\n"
        .ascii  ".clear_stack:\n"
        .ascii  "\tcmpq $"
.L_RODATA_header3: # 91 bytes
        .ascii  ", %r8\n"
        .ascii  "\tje .start\n"
        .ascii  "\tmovb $0, (%rsp, %r8)\n"
        .ascii  "\tincq %r8\n"
        .ascii  "\tjmp .clear_stack\n"
        .ascii  ".start:\n"
        .ascii  "\txorq %r8, %r8\n"
        .ascii  "\n"

# End
.L_RODATA_end1: # 8 bytes
        .ascii  "\n"
        .ascii  "\taddq $"
.L_RODATA_end2: # 50 bytes
        .ascii  ", %rsp\n"
        .ascii  "\n"
        .ascii  "\tmovq $60, %rax\n"
        .ascii  "\txorq %rdi, %rdi\n"
        .ascii  "\tsyscall\n"

# Operations
.L_RODATA_output_op: # 78 bytes
        .ascii  "\tmovq $1, %rax\n"
        .ascii  "\tmovq $1, %rdi\n"
        .ascii  "\tleaq (%rsp, %r8), %rsi\n"
        .ascii  "\tmovq $1, %rdx\n"
        .ascii  "\tsyscall\n"

.L_RODATA_input_op: # 82 bytes
        .ascii  "\txorq %rax, %rax\n"
        .ascii  "\txorq %rdi, %rdi\n"
        .ascii  "\tleaq (%rsp, %r8), %rsi\n"
        .ascii  "\tmovq $1, %rdx\n"
        .ascii  "\tsyscall\n"

.L_RODATA_rarrow_once: # 10 bytes
        .ascii  "\tincq %r8\n"
.L_RODATA_rarrow_mul1: # 7 bytes
        .ascii  "\taddq $"
.L_RODATA_rarrow_mul2: # 6 bytes
        .ascii  ", %r8\n"

.L_RODATA_larrow_once: # 10 bytes
        .ascii  "\tdecq %r8\n"
.L_RODATA_larrow_mul1: # 7 bytes
        .ascii  "\tsubq $"
.L_RODATA_larrow_mul2: # 6 bytes
        .ascii  ", %r8\n"

.L_RODATA_plus_once: # 18 bytes
        .ascii  "\tincb (%rsp, %r8)\n"
.L_RODATA_plus_mul1: # 7 bytes
        .ascii  "\taddb $"
.L_RODATA_plus_mul2: # 14 bytes
        .ascii  ", (%rsp, %r8)\n"

.L_RODATA_minus_once: # 18 bytes
        .ascii  "\tdecb (%rsp, %r8)\n"
.L_RODATA_minus_mul1: # 7 bytes
        .ascii  "\tsubb $"
.L_RODATA_minus_mul2: # 14 bytes
        .ascii  ", (%rsp, %r8)\n"

.L_RODATA_label_prefix: # 2 bytes
        .ascii  ".L"
.L_RODATA_label_suffix: # 2 bytes
        .ascii  ":\n"

.L_RODATA_open_brack1: # 28 bytes
        .ascii  "\tcmpb $0, (%rsp, %r8)\n"
        .ascii  "\tje .L"
.L_RODATA_open_brack2: # 5 bytes
        .ascii  ".end\n"

.L_RODATA_close_brack1: # 7 bytes
        .ascii  "\tjmp .L"
.L_RODATA_close_brack2: # 1 byte
        .ascii  "\n"
.L_RODATA_close_brack3: # 6 bytes
        .ascii  ".end:\n"

### Messages ###
.L_MSG_success:
        .asciz  "Success, \"out.S\" is generated."

.L_MSG_no_input_file:
        .asciz  "Input file must be provided."

.L_MSG_failed_to_open_input:
        .asciz  "Failed to open input file."

.L_MSG_failed_to_open_output:
        .asciz  "Failed to open output file."

.L_MSG_close_loop_error:
        .asciz  "Failed to find matching loop opening for loop close."

### Data ###
.L_DATA_argc:
        .long   0

.L_DATA_argv:
        .quad   0

.L_DATA_file_stat: # 144 bytes (18 quads)
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0
        .quad   0

.L_DATA_numbuf: # 16 bytes
        .quad   0
        .quad   0
