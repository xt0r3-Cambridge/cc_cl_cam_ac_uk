let fib( m : int) : int = 
    try
        if m < 0
            then raise -1
        else if m = 0
            then 1 
            else if m = 1 
                then 1 
                else fib (m - 1) + fib (m - 2) 
                end 
            end 
        end
    except e
        e
in 
    fib(?) 
end 
