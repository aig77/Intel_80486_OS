import "io"

// each newvec allocation also dedicates four bytes:
//  -3: size -- (even number = unoccupied chunk, odd number = occupied chunk)
//  -2: address of previous memory chunk
//  -1: address of next memory chunk
//   0: (this is the address returned to user)
//   1:
//    :
// n-1:
//   n: size -- (even number = unoccupied chunk, odd number = occupied chunk)

// the heap starts with an array 42 words long (0-41)
// this contains 14 entries, each a pointer (or null)
// to a doubly linked list of initally unallocated chunks
// of a delimited size following the pattern:
//  2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 32768

// in addition to each of the 14 entries in the array of pointers to lists
// there are two additonal entries which follow right after the ptr_to_list
// 0: ptr_to_list
// 1: ptr_to_free_list
// 2: items_in_free_list

// when new_vec is called it first checks the corresponding free list.
// if adequately sized chunk in the free list is found then
//    + new_vec returns the adress of that chunk
//    + and moves that chunk from the free list to the occupied list.
// else if the free list is empty or does not contain a chunk of adequate size then
//    + new_vec allocates a chunk of the requested size
//    + and adds it to the front of the list

// when free_vec is called the allocated chunk is moved to the appropriate free list
// to be recycled when new_vec asks for a chunk <= the size of that free chunk

// the heap starts off as one page (2048 words / 8192 bytes) and may grow to up to
// 32 pages as needed (ihandle_pagefault takes care of growing the heap)

// max sizeof new chunk is 16 pages / 131 MB


export{ new_vec, free_vec, init_heap }

manifest
{
    chunk_size = -3,
    previous   = -2,
    next       = -1
}

manifest
{
    sizeof_meta_data      = 3,
    sizeof_all_meta_data  = 4,
    sizeof_array_of_lists = 42
}

manifest
{
    max_size = 32768 //words
}

static { heap, next_free_address }

let error(error_code) be
{
    out("error %d, error_code\n");
    if error_code = 1 then
    {
        out("newvec: requested too large of a chunk. max size = 32768 words\n")
    }
    resultis 0
}

let print_memory(address) be
{
    for i = 0 to 75 do
    {
        out("heap ! %d = ", i);
        out("0x%x: %d / 0x%x\n", @(address ! i), address ! i, address ! i)
    }
}

//all chunks returned to user are even number of words
let set_chunk_size(size) be
{
    if size rem 2 = 1 then size +:= 1;
    if size > max_size then resultis error(1);
    resultis size
}

//odd size signals chunk is occupied (w/ size-1 words)
let chunk_is_occupied(address) be
{
    if (address ! chunk_size) rem 2 = 1 then resultis true;
    resultis false
}

let get_index_in_array_of_lists(size) be
{
    let index = 0, current_power_of_two = 2;
    while current_power_of_two <= 8192 do
    {
        if size <= current_power_of_two then
        {
            resultis index;
        }
        index +:= 3;
        current_power_of_two *:= 2
    }
    resultis index
}

let address_is_ptr_to_list(addr) be
{
    if addr >= heap /\ addr < (heap + sizeof_array_of_lists) then
    {
        resultis true;
    }
    resultis false
}

let new_chunk(size, index) be
{
    let prev_ptr = @(heap ! index);
    let next_ptr = heap ! index;
    let addr = next_free_address;
    next_free_address +:= (size + sizeof_all_meta_data);
    if next_ptr <> nil then
    {
        next_ptr ! previous := addr;
    }
    addr ! chunk_size := size + 1;
    addr ! previous   := prev_ptr;
    addr ! next       := next_ptr;
    addr ! size       := size + 1;
    resultis addr
}

let move_free_chunk_to_list(addr, index) be
{
    let prev_ptr  = @(heap ! index);
    let next_ptr  = heap ! index;
    let size      = addr ! chunk_size;
    test (addr ! previous) = @(heap ! (index + 1)) then
    {
        heap ! (index + 1) := addr ! next
    }
    else
    {
        (addr ! previous) ! next := addr ! next;
    }

    if addr ! next <> nil then
    {
        (addr ! next) ! previous := addr ! previous;
    }
    if next_ptr <> nil then
    {
        next_ptr ! previous := addr;
    }
    addr ! chunk_size := size + 1;
    addr ! previous   := prev_ptr;
    addr ! next       := next_ptr;
    addr ! size       := size + 1;
    heap ! (index + 2) -:= 1;
    resultis addr
}

let recycle_free_chunk(size, index) be
{
    let prev_ptr = @(heap ! index);
    let next_ptr = heap ! index;
    let addr = heap ! (index + 1);
    until addr = nil do
    {
        if addr ! chunk_size >= size then
        {
            resultis move_free_chunk_to_list(addr, index);
        }
        addr := addr ! next
    }
    resultis new_chunk(size, prev_ptr, next_ptr)
}

//add to front of list (either new_chunk or recycle_free_chunk)
let new_vec(size) be
{
    let index, free_list_ptr, items_in_free_list;
    let next_ptr, prev_ptr;
    size  := set_chunk_size(size);
    index := get_index_in_array_of_lists(size);
    items_in_free_list := heap ! (index + 2);
    test items_in_free_list = 0 then
    {
        heap ! index := new_chunk(size, index)
    }
    else
    {
        heap ! index := recycle_free_chunk(size, index);
    }
    resultis (heap ! index)
}

let move_chunk_to_free_list(addr, size) be
{
    let index = get_index_in_array_of_lists(size);
    let prev_ptr = @(heap ! (index + 1));
    let next_ptr = heap ! (index + 1);
    test (addr ! previous) = @(heap ! index) then
    {
        heap ! index := addr ! next
    }
    else
    {
        (addr ! previous) ! next := addr ! next;
    }

    if addr ! next <> nil then
    {
        (addr ! next) ! previous := addr ! previous;
    }
    if next_ptr <> nil then
    {
        next_ptr ! previous := addr;
    }
    addr ! previous := prev_ptr;
    addr ! next     := next_ptr;
    heap ! (index + 1) := addr;
    heap ! (index + 2) +:= 1 }

let free_vec(addr) be
{
    let size = addr ! chunk_size;
    //out("\nfree 0x%x, IS > 0x%x AND < 0x%x\n", addr, (heap + 45), next_free_address);
    if addr < (heap + 45) \/ addr > next_free_address then
    {
        out("Called freevec on non-heap memory\n");
        return
    }
    if ~chunk_is_occupied(addr) then
    {
        out("memory is already free\n");
        return
    }
    size -:= 1;
    addr ! chunk_size := size;
    addr ! size       := size;
    move_chunk_to_free_list(addr, size)
}

let print_heap() be
{
    for i = 0 to 100 do
    {
        out("0x%x || ", @(heap ! i));
        out("%d: ", i);
        test heap ! i < 10000 then out("%d", heap ! i)
        else out("0x%x", heap ! i);
        out("\n")
    }
}

let init_heap(heap_address) be
{ heap := heap_address;
  next_free_address := heap + sizeof_array_of_lists + sizeof_meta_data }


let test_run() be
{ let x, y, z;
  x := newvec(10);
  y := newvec(12);
  z := newvec(15);
  out("x = 0x%x\n\n", x);
  out("y = 0x%x\n\n", y);
  out("z = 0x%x\n\n", z);
  print_heap();
  out("\n\n\n");
  freevec(x);
  freevec(y);
  freevec(z);
  print_heap();
  out("\n\n\n");
  y := newvec(12);
  z := newvec(11);
  print_heap();
}
